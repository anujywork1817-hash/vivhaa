import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../chat/data/chat_socket_service.dart';
import '../../data/api_call_repository.dart';
import '../../domain/call_repository.dart';

enum CallStatus { idle, calling, ringing, connected, ended }

enum CallEndReason { remoteEnded, rejected, busy, timeout, permissionDenied, connectionFailed, error }

class CallState {
  final CallStatus status;
  final String? callId;
  final bool isCaller;
  final String peerUserId;
  final String peerName;
  final String? peerPhotoUrl;
  final bool micMuted;
  final bool cameraOff;
  final bool isVideo;
  // Speakerphone vs. earpiece routing — only meaningful (and only shown
  // in the UI) for voice calls; video calls stay on whatever the OS
  // defaults to since the phone isn't held to the ear while looking at
  // the screen. Defaults to false (earpiece) to match standard phone-call
  // behavior — see CallController._markConnected, which also forces the
  // OS-level route to match this default at connect time.
  final bool speakerOn;
  final Duration duration;
  final String? errorMessage;
  final CallEndReason? endReason;

  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.isCaller = false,
    this.peerUserId = '',
    this.peerName = '',
    this.peerPhotoUrl,
    this.micMuted = false,
    this.cameraOff = false,
    this.isVideo = true,
    this.speakerOn = false,
    this.duration = Duration.zero,
    this.errorMessage,
    this.endReason,
  });

  bool get isActive => status != CallStatus.idle && status != CallStatus.ended;

  CallState copyWith({
    CallStatus? status,
    String? callId,
    bool? isCaller,
    String? peerUserId,
    String? peerName,
    String? peerPhotoUrl,
    bool? micMuted,
    bool? cameraOff,
    bool? isVideo,
    bool? speakerOn,
    Duration? duration,
    String? errorMessage,
    CallEndReason? endReason,
  }) {
    return CallState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      isCaller: isCaller ?? this.isCaller,
      peerUserId: peerUserId ?? this.peerUserId,
      peerName: peerName ?? this.peerName,
      peerPhotoUrl: peerPhotoUrl ?? this.peerPhotoUrl,
      micMuted: micMuted ?? this.micMuted,
      cameraOff: cameraOff ?? this.cameraOff,
      isVideo: isVideo ?? this.isVideo,
      speakerOn: speakerOn ?? this.speakerOn,
      duration: duration ?? this.duration,
      errorMessage: errorMessage,
      endReason: endReason,
    );
  }
}

/// Owns the RTCPeerConnection lifecycle, local/remote media, and the
/// idle -> calling/ringing -> connected -> ended state machine for one
/// call at a time. Signaling rides the same WebSocket connection chat
/// already uses ([ChatSocketService]) — call:* events are just JSON
/// frames with a "type" field, exactly like chat's "message" events.
class CallController extends StateNotifier<CallState> {
  final ChatSocketService _socket;
  final CallRepository _callRepository;

  StreamSubscription? _socketSubscription;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;
  // Mirrors remoteStream: local media becomes available asynchronously
  // (behind a user-paced permission dialog + getUserMedia), on a timeline
  // ActiveCallScreen's init has no way to know about otherwise. Without
  // this, a screen that reads the plain snapshot before local media is
  // ready has no way to learn it later became ready — see
  // localStreamValue's doc for why the snapshot alone isn't enough.
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  // Snapshot for a screen that mounts after local media is already open
  // (a broadcast stream doesn't replay past events to a late subscriber) —
  // same reasoning as remoteStreamValue below.
  MediaStream? get localStreamValue => _localStream;
  // The peer connection (and its onTrack callback) exists before
  // ActiveCallScreen does — acceptCall()/startCall() create it, but the
  // screen only appears afterward and needs a moment to initialize its
  // renderers. A broadcast stream doesn't replay past events to a
  // subscriber that arrives late, so if the remote track arrives in that
  // window (very possible once ICE is already connected), the screen's
  // subscription would simply never see it. This snapshot lets the
  // screen check "is there already a remote stream" on init instead of
  // only ever reacting to future ones.
  MediaStream? get remoteStreamValue => _remoteStream;
  MediaStream? _remoteStream;

  Timer? _ringTimeoutTimer;
  Timer? _durationTimer;
  Timer? _reconnectGraceTimer;
  DateTime? _connectedAt;

  // Bounds how many ICE-restart attempts _attemptIceRestart makes before
  // giving up and ending the call — reset to 0 whenever ICE gets back to
  // connected/completed, so a call that recovers and later degrades again
  // gets a full fresh set of attempts rather than accumulating forever.
  static const _maxIceRestartAttempts = 3;
  int _iceRestartAttempts = 0;

  // ICE candidates that arrive before the remote description is set
  // (common — ICE gathering starts immediately, signaling is async) are
  // buffered here and flushed once setRemoteDescription completes.
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  Map<String, dynamic>? _pendingOffer;

  // The caller's own outgoing candidates gathered before the server's
  // call:ringing ack tells us our call_id (there's necessarily a gap
  // between sending call:initiate and hearing back) — sent with no
  // call_id, the server can't route them to anyone. Buffered here and
  // flushed once state.callId is set.
  final List<Map<String, dynamic>> _pendingLocalCandidates = [];

  CallController(this._socket, this._callRepository) : super(const CallState()) {
    _socketSubscription = _socket.events.listen(_onSocketEvent);
  }

  void _onSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final data = event['data'] as Map<String, dynamic>?;
    if (type == 'call:incoming' ||
        type == 'call:ringing' ||
        type == 'call:accept' ||
        type == 'call:reject' ||
        type == 'call:busy' ||
        type == 'call:timeout' ||
        type == 'call:end' ||
        (type == 'error' && state.status == CallStatus.calling)) {
      debugPrint('CallController: received "$type" while status=${state.status} — $data');
    }
    if (type == null || data == null) return;

    // Every call:initiate rejection (not a mutual match, blocked, callee
    // offline, self-call) comes back as a generic {"type":"error",...}
    // event, not a "call:"-prefixed one — chat's HandleIncoming uses the
    // same shape for its own errors. Without this, a rejected call just
    // leaves the caller's screen on "Calling…" forever with no
    // explanation, indistinguishable from a call that's still ringing.
    if (type == 'error' && state.status == CallStatus.calling) {
      _onInitiateError(data['message'] as String?);
      return;
    }

    if (!type.startsWith('call:')) return;

    switch (type) {
      case 'call:ringing':
        _onRinging(data);
      case 'call:incoming':
        _onIncoming(data);
      case 'call:accept':
        _onAccepted(data);
      case 'call:reject':
        _onRemoteEnded(CallEndReason.rejected);
      case 'call:busy':
        _onRemoteEnded(CallEndReason.busy);
      case 'call:timeout':
        _onRemoteEnded(CallEndReason.timeout);
      case 'call:ice-candidate':
        _onRemoteIceCandidate(data);
      case 'call:renegotiate-offer':
        _onRenegotiateOffer(data);
      case 'call:renegotiate-answer':
        _onRenegotiateAnswer(data);
      case 'call:end':
        _onRemoteEnded(CallEndReason.remoteEnded);
    }
  }

  Future<void> _onInitiateError(String? message) async {
    _ringTimeoutTimer?.cancel();
    await _cleanupMedia();
    state = CallState(
      status: CallStatus.ended,
      endReason: CallEndReason.error,
      errorMessage: message ?? 'Could not place the call.',
    );
    _reset(afterDelay: true);
  }

  /// The server's ack that call:initiate went through — carries the
  /// call_id the caller needs to route ICE candidates and end the call,
  /// mirroring what the callee already gets from call:incoming.
  void _onRinging(Map<String, dynamic> data) {
    if (state.status != CallStatus.calling) return;
    state = state.copyWith(callId: data['call_id'] as String?);
    _flushPendingLocalCandidates();
  }

  void _onIncoming(Map<String, dynamic> data) {
    // Already on a call — the server also enforces "one active call per
    // user" and would send call:busy to the new caller, but a client-side
    // guard means we never even show a second incoming-call UI locally.
    if (state.isActive) return;

    _pendingOffer = data['offer'] as Map<String, dynamic>?;
    state = CallState(
      status: CallStatus.ringing,
      callId: data['call_id'] as String,
      isCaller: false,
      peerUserId: data['caller_id'] as String,
      peerName: (data['caller_name'] as String?) ?? 'Someone',
      // Every call:incoming before is_video existed was a video call, so a
      // missing field defaults to true — mirrors the backend's default.
      isVideo: (data['is_video'] as bool?) ?? true,
    );
  }

  /// Caller flow: request permissions/media, create the peer connection,
  /// send the offer, and start ringing.
  Future<void> startCall({
    required String peerUserId,
    required String peerName,
    String? peerPhotoUrl,
    bool isVideo = true,
  }) async {
    if (state.isActive) return;

    final granted = await _ensurePermissions(isVideo);
    if (!granted) {
      state = CallState(
        status: CallStatus.ended,
        endReason: CallEndReason.permissionDenied,
        errorMessage: isVideo
            ? 'Camera and microphone access are required to make a call.'
            : 'Microphone access is required to make a call.',
      );
      return;
    }

    state = CallState(
      status: CallStatus.calling,
      isCaller: true,
      peerUserId: peerUserId,
      peerName: peerName,
      peerPhotoUrl: peerPhotoUrl,
      isVideo: isVideo,
    );

    try {
      await _openLocalMedia(isVideo);
      final pc = await _createPeerConnection();
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      _socket.send({
        'type': 'call:initiate',
        'callee_id': peerUserId,
        'is_video': isVideo,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });

      // Client-side safety net mirroring the server's 30s ring timeout —
      // if for any reason the server-side timer's call:timeout never
      // arrives (dropped frame, reconnect gap), the caller's screen still
      // doesn't hang forever.
      _ringTimeoutTimer = Timer(const Duration(seconds: 32), () {
        if (state.status == CallStatus.calling) {
          _onRemoteEnded(CallEndReason.timeout);
        }
      });
    } catch (e) {
      await _cleanupMedia();
      state = CallState(status: CallStatus.ended, endReason: CallEndReason.error, errorMessage: e.toString());
    }
  }

  /// Callee flow: only now (on explicit accept, not on the incoming ring)
  /// do we touch the camera/mic — grabbing media before the user has
  /// agreed to answer would be a surprise permission prompt on an
  /// incoming call they haven't even looked at yet.
  Future<void> acceptCall() async {
    if (state.status != CallStatus.ringing || _pendingOffer == null) return;

    final granted = await _ensurePermissions(state.isVideo);
    if (!granted) {
      _socket.send({'type': 'call:reject', 'call_id': state.callId});
      state = CallState(
        status: CallStatus.ended,
        endReason: CallEndReason.permissionDenied,
        errorMessage: state.isVideo
            ? 'Camera and microphone access are required to answer a call.'
            : 'Microphone access is required to answer a call.',
      );
      return;
    }

    try {
      await _openLocalMedia(state.isVideo);
      final pc = await _createPeerConnection();
      _localStream!.getTracks().forEach((track) => pc.addTrack(track, _localStream!));

      await pc.setRemoteDescription(
        RTCSessionDescription(_pendingOffer!['sdp'] as String, _pendingOffer!['type'] as String),
      );
      await _flushPendingCandidates();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _socket.send({
        'type': 'call:accept',
        'call_id': state.callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });

      _markConnected();
    } catch (e) {
      await _cleanupMedia();
      state = CallState(status: CallStatus.ended, endReason: CallEndReason.error, errorMessage: e.toString());
    }
  }

  void rejectCall() {
    if (state.status != CallStatus.ringing) return;
    _socket.send({'type': 'call:reject', 'call_id': state.callId});
    _reset();
  }

  Future<void> endCall({String reason = 'ended'}) async {
    if (!state.isActive) return;
    _socket.send({'type': 'call:end', 'call_id': state.callId, 'reason': reason});
    await _cleanupMedia();
    state = state.copyWith(status: CallStatus.ended, endReason: CallEndReason.remoteEnded);
    _reset(afterDelay: true);
  }

  // BUG-CRIT-02: setRemoteDescription and _flushPendingCandidates were
  // both fired without awaiting, from a sync method. Dart runs an async
  // call synchronously only up to its first internal await, then returns
  // control immediately — setRemoteDescription's native/plugin call
  // hadn't actually completed by the time _flushPendingCandidates ran
  // addCandidate calls right after it, so the underlying WebRTC layer
  // saw candidates arrive before the remote description was applied and
  // threw "remote description must be set before adding candidates".
  // Making this async and awaiting each step in order is the fix; it's
  // still called fire-and-forget from the sync WS event switch above,
  // which is fine — nothing there needs to block on a call being fully
  // connected.
  Future<void> _onAccepted(Map<String, dynamic> data) async {
    if (state.status != CallStatus.calling) return;
    _ringTimeoutTimer?.cancel();
    // Defensive — call:ringing should already have set this, but an
    // accept that raced ahead of it (or arrived on a reconnect) shouldn't
    // leave callId null for the rest of the call.
    if (data['call_id'] != null) {
      state = state.copyWith(callId: data['call_id'] as String);
      _flushPendingLocalCandidates();
    }
    final answer = data['answer'] as Map<String, dynamic>;
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
    );
    await _flushPendingCandidates();
    _markConnected();
  }

  void _markConnected() {
    debugPrint('CallController: _markConnected (callId=${state.callId}, isCaller=${state.isCaller})');
    _connectedAt = DateTime.now();
    state = state.copyWith(status: CallStatus.connected, duration: Duration.zero, speakerOn: false);
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt == null) return;
      state = state.copyWith(duration: DateTime.now().difference(_connectedAt!));
    });
    // Force the OS-level route to match state.speakerOn's earpiece
    // default — the platform's own default route isn't guaranteed to be
    // the earpiece (some devices/OEMs default a fresh audio session to
    // speaker), and this is voice-only; video calls leave routing alone.
    if (!state.isVideo) {
      Helper.setSpeakerphoneOn(false);
    }
  }

  Future<void> _onRemoteIceCandidate(Map<String, dynamic> data) async {
    final raw = data['candidate'] as Map<String, dynamic>?;
    if (raw == null) return;
    final candidate = RTCIceCandidate(
      raw['candidate'] as String?,
      raw['sdpMid'] as String?,
      (raw['sdpMLineIndex'] as num?)?.toInt(),
    );
    final hasRemoteDesc =
        _peerConnection != null && (await _peerConnection!.getRemoteDescription()) != null;
    debugPrint('CallController: remote ICE candidate received (hasRemoteDesc=$hasRemoteDesc): ${candidate.candidate}');
    if (!hasRemoteDesc) {
      _pendingRemoteCandidates.add(candidate);
    } else {
      await _peerConnection!.addCandidate(candidate);
    }
  }

  Future<void> _flushPendingCandidates() async {
    for (final c in _pendingRemoteCandidates) {
      await _peerConnection?.addCandidate(c);
    }
    _pendingRemoteCandidates.clear();
  }

  /// Callee side of an ICE restart: the caller drives recovery (see
  /// _attemptIceRestart), we just answer whatever restart offer arrives.
  /// setRemoteDescription with a fresh offer on an already-established
  /// connection is exactly how WebRTC renegotiation works — no need to
  /// tear anything down first.
  Future<void> _onRenegotiateOffer(Map<String, dynamic> data) async {
    final offer = data['offer'] as Map<String, dynamic>?;
    if (offer == null || _peerConnection == null) return;
    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
      );
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _socket.send({
        'type': 'call:renegotiate-answer',
        'call_id': state.callId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (e) {
      debugPrint('CallController: failed to answer ICE restart offer — $e');
      // No explicit failure signal needed here — the ICE connection state
      // machine (still watching the same peer connection) will see this
      // restart didn't help and either the caller retries or gives up.
    }
  }

  /// Caller side of an ICE restart: apply the callee's answer to the
  /// restart offer we sent in _attemptIceRestart.
  Future<void> _onRenegotiateAnswer(Map<String, dynamic> data) async {
    final answer = data['answer'] as Map<String, dynamic>?;
    if (answer == null || _peerConnection == null) return;
    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
      );
    } catch (e) {
      debugPrint('CallController: failed to apply ICE restart answer — $e');
    }
  }

  /// Attempts to recover a degraded connection via ICE restart before
  /// giving up on the call outright. Only the caller side drives this —
  /// letting both peers independently restart risks racing offers
  /// against each other (SDP glare); the callee side only ever responds
  /// to whatever restart offer arrives (_onRenegotiateOffer). Bounded to
  /// [_maxIceRestartAttempts] tries; only after those are exhausted does
  /// this actually end the call, mirroring what the old passive-wait
  /// logic did unconditionally after 8s.
  Future<void> _attemptIceRestart() async {
    if (!state.isActive || !state.isCaller || _peerConnection == null) return;

    if (_iceRestartAttempts >= _maxIceRestartAttempts) {
      debugPrint('CallController: ICE restart exhausted after $_iceRestartAttempts attempts, ending call');
      _socket.send({'type': 'call:end', 'call_id': state.callId, 'reason': 'connection_failed'});
      await _onRemoteEnded(CallEndReason.connectionFailed);
      return;
    }

    _iceRestartAttempts++;
    debugPrint('CallController: attempting ICE restart ($_iceRestartAttempts/$_maxIceRestartAttempts)');
    try {
      await _peerConnection!.restartIce();
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _socket.send({
        'type': 'call:renegotiate-offer',
        'call_id': state.callId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      debugPrint('CallController: ICE restart attempt failed to send — $e');
      // Couldn't even get a restart offer out (peer connection in a bad
      // state) — no point waiting for a response that'll never come.
      _socket.send({'type': 'call:end', 'call_id': state.callId, 'reason': 'connection_failed'});
      await _onRemoteEnded(CallEndReason.connectionFailed);
    }
  }

  void _flushPendingLocalCandidates() {
    if (state.callId == null) return;
    for (final payload in _pendingLocalCandidates) {
      _socket.send({...payload, 'call_id': state.callId});
    }
    _pendingLocalCandidates.clear();
  }

  Future<void> _onRemoteEnded(CallEndReason reason) async {
    if (!state.isActive) return;
    await _cleanupMedia();
    state = state.copyWith(status: CallStatus.ended, endReason: reason);
    _reset(afterDelay: true);
  }

  Future<bool> _ensurePermissions(bool isVideo) async {
    final permissions = isVideo ? [Permission.camera, Permission.microphone] : [Permission.microphone];
    final statuses = await permissions.request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _openLocalMedia(bool isVideo) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    });
    _localStreamController.add(_localStream);
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final iceServersResult = await _callRepository.getIceServers();
    final iceServers = iceServersResult.when(
      success: (servers) => servers.map((s) => s.toRtcConfig()).toList(),
      // Google's public STUN is still a reasonable fallback if the ICE
      // servers fetch itself fails — better than a call that can't even
      // attempt NAT traversal.
      failure: (_) => [
        {
          'urls': ['stun:stun.l.google.com:19302']
        }
      ],
    );

    debugPrint('CallController: ICE servers = $iceServers');
    final pc = await createPeerConnection({'iceServers': iceServers});

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      final payload = {
        'type': 'call:ice-candidate',
        'call_id': state.callId,
        'target_user_id': state.peerUserId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      };
      debugPrint('CallController: local ICE candidate (callId=${state.callId}): ${candidate.candidate}');
      // The callee always has callId by the time its peer connection
      // exists (set from call:incoming before acceptCall() runs). The
      // caller doesn't — its peer connection (and ICE gathering) starts
      // in startCall(), before the server's call:ringing ack can
      // possibly have arrived yet — so a null callId here means "buffer
      // until it's known," not "something's wrong."
      if (state.callId == null) {
        _pendingLocalCandidates.add(payload);
      } else {
        _socket.send(payload);
      }
    };

    pc.onTrack = (event) {
      debugPrint('CallController: onTrack fired, streams=${event.streams.length}, kind=${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };

    pc.onIceConnectionState = (iceState) {
      debugPrint('CallController: ICE connection state -> $iceState');
      _onIceConnectionStateChange(iceState);
    };
    pc.onConnectionState = (connState) {
      debugPrint('CallController: peer connection state -> $connState');
    };

    _peerConnection = pc;
    return pc;
  }

  /// A dropped connection doesn't necessarily mean the call is over —
  /// WebRTC can and often does recover from a brief 'disconnected' blip
  /// (a wifi hiccup, a network handoff) on its own. 'failed' and a
  /// 'disconnected' that outlasts the grace period both attempt an ICE
  /// restart (_attemptIceRestart) before the call is torn down — only
  /// once those attempts are exhausted does this actually end the call.
  ///
  /// Only the caller may renegotiate/restart ICE (avoids both sides
  /// racing to offer at once) — but that used to mean the CALLEE had no
  /// fallback at all: _attemptIceRestart no-ops for a non-caller, so if
  /// the signaling call:end message ever got lost (a dropped socket, the
  /// app backgrounded right as the other side hung up — the WS delivery
  /// here is fire-and-forget with no retry, see websocket.Hub.SendToUser),
  /// the callee's screen was stuck reading "Connected" forever with
  /// nothing left to notice the call was actually over. The callee now
  /// gets its own give-up path: it can't restart the connection, but it
  /// can still declare the call over once it's clear nothing is coming
  /// back, the same way the caller eventually does.
  void _onIceConnectionStateChange(RTCIceConnectionState iceState) {
    switch (iceState) {
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _reconnectGraceTimer?.cancel();
        _reconnectGraceTimer = Timer(const Duration(seconds: 8), () {
          if (state.status == CallStatus.connected) {
            _giveUpOnConnection();
          }
        });
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _reconnectGraceTimer?.cancel();
        _iceRestartAttempts = 0;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _reconnectGraceTimer?.cancel();
        // 'failed' is already terminal — unlike 'disconnected', there's
        // no self-healing grace period worth waiting out.
        _giveUpOnConnection();
      default:
        break;
    }
  }

  Future<void> _giveUpOnConnection() async {
    if (state.isCaller) {
      await _attemptIceRestart();
      return;
    }
    if (!state.isActive) return;
    debugPrint('CallController: connection lost with no restart path (callee) — ending call locally');
    // Best-effort notice in case the other side is the one actually stuck
    // (e.g. its own signaling channel is still fine but media died) — not
    // required for this side to stop showing a dead call as connected.
    _socket.send({'type': 'call:end', 'call_id': state.callId, 'reason': 'connection_failed'});
    await _onRemoteEnded(CallEndReason.connectionFailed);
  }

  void toggleMic() {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track == null) return;
    track.enabled = state.micMuted;
    state = state.copyWith(micMuted: !state.micMuted);
  }

  void toggleCamera() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    track.enabled = state.cameraOff;
    state = state.copyWith(cameraOff: !state.cameraOff);
  }

  /// Voice-call only (see CallState.speakerOn) — switches OS-level audio
  /// routing between earpiece and loudspeaker. Turning the speaker ON
  /// uses setSpeakerphoneOnButPreferBluetooth rather than a plain
  /// setSpeakerphoneOn(true): flutter_webrtc has no API on this version
  /// to detect a connected headset (so the toggle can't hide/disable
  /// itself when one's active, see active_call_screen.dart's note), but
  /// this at least avoids blasting the loudspeaker over a paired
  /// Bluetooth headset if one happens to be connected. Turning it back
  /// off always means the earpiece specifically, so a plain
  /// setSpeakerphoneOn(false) is unambiguous.
  void toggleSpeaker() {
    final next = !state.speakerOn;
    state = state.copyWith(speakerOn: next);
    if (next) {
      Helper.setSpeakerphoneOnButPreferBluetooth();
    } else {
      Helper.setSpeakerphoneOn(false);
    }
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    await Helper.switchCamera(track);
  }

  /// Closes the peer connection and stops every local media track. Called
  /// on every exit path (reject/end/error) — a WebRTC connection or an
  /// active camera/mic track left dangling after a call ends is exactly
  /// the "camera light stays on" bug this guards against.
  Future<void> _cleanupMedia() async {
    _ringTimeoutTimer?.cancel();
    _durationTimer?.cancel();
    _reconnectGraceTimer?.cancel();
    _pendingRemoteCandidates.clear();
    _pendingLocalCandidates.clear();
    _pendingOffer = null;
    _connectedAt = null;
    _iceRestartAttempts = 0;

    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);

    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _peerConnection = null;

    _remoteStream = null;
    _remoteStreamController.add(null);
  }

  void _reset({bool afterDelay = false}) {
    void doReset() {
      if (mounted) state = const CallState();
    }

    if (afterDelay) {
      // Briefly leaves the "call ended" reason visible on the active-call
      // screen before it pops itself, instead of vanishing mid-explanation.
      Timer(const Duration(seconds: 2), doReset);
    } else {
      doReset();
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _cleanupMedia();
    _remoteStreamController.close();
    _localStreamController.close();
    super.dispose();
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Kept alive for the app session, like [chatSocketServiceProvider] — a
/// call and its incoming-call listener need to survive screen navigation
/// (an incoming call can arrive while the user is anywhere in the app).
final callControllerProvider = StateNotifierProvider<CallController, CallState>((ref) {
  return CallController(ref.watch(chatSocketServiceProvider), ref.watch(callRepositoryProvider));
});
