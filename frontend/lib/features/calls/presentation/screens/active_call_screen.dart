import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/misc/profile_avatar.dart';
import '../controllers/call_controller.dart';

/// Active call: remote video fills the screen, local video is a small
/// draggable PiP over it, with mute/camera/switch-camera/end controls and
/// a live duration timer. Also covers the "calling…" (ringing-out) and
/// "call ended" states so the caller never sees a blank screen between
/// dialing and either side answering.
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  Offset _pipOffset = const Offset(16, 60);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    final controller = ref.read(callControllerProvider.notifier);
    // The local track can just as easily arrive after this screen exists
    // as the remote one can — _openLocalMedia() sits behind a user-paced
    // permission dialog + getUserMedia, neither of which is guaranteed to
    // finish before initState runs. Snapshot what's already there, then
    // listen for it becoming available later — same pattern as remote.
    _localRenderer.srcObject = controller.localStreamValue;
    controller.localStream.listen((stream) {
      if (!mounted) return;
      setState(() => _localRenderer.srcObject = stream);
    });
    // The remote track can arrive (onTrack) before this screen exists —
    // the peer connection is created back in acceptCall()/startCall(),
    // and initializing these renderers just now took real time. A
    // broadcast stream subscription only catches *future* events, so
    // check for one that's already there first.
    _remoteRenderer.srcObject = controller.remoteStreamValue;
    controller.remoteStream.listen((stream) {
      if (!mounted) return;
      setState(() => _remoteRenderer.srcObject = stream);
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _endReasonLabel(CallEndReason? reason) {
    return switch (reason) {
      CallEndReason.rejected => 'Call declined',
      CallEndReason.busy => 'They\'re on another call',
      CallEndReason.timeout => 'No answer',
      CallEndReason.permissionDenied => 'Camera/microphone access denied',
      CallEndReason.connectionFailed => 'Connection lost',
      CallEndReason.error => 'Something went wrong',
      _ => 'Call ended',
    };
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callControllerProvider);

    ref.listen(callControllerProvider, (previous, next) {
      // CallController resets to idle ~2s after ending (see _reset) so
      // the "call ended" reason stays visible briefly — once it does,
      // this screen has nothing left to show and closes itself.
      if (next.status == CallStatus.idle && previous?.status != CallStatus.idle) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });

    return PopScope(
      canPop: call.status == CallStatus.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(callControllerProvider.notifier).endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_showRemoteVideo(call))
              Positioned.fill(child: RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
            else
              _CenteredPeerInfo(call: call, statusLabel: _statusLabel(call)),

            if (call.status == CallStatus.ended)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Text(
                    _endReasonLabel(call.endReason),
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),

            if (call.isVideo && call.status == CallStatus.connected)
              Positioned(
                left: _pipOffset.dx,
                top: _pipOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) => setState(() => _pipOffset += details.delta),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    child: SizedBox(
                      width: 100,
                      height: 140,
                      child: call.cameraOff
                          ? ColoredBox(color: Colors.grey.shade900, child: const Icon(Icons.videocam_off_rounded, color: Colors.white38))
                          : RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(call.peerName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      if (call.status == CallStatus.connected)
                        Text(_formatDuration(call.duration), style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),

            if (call.status != CallStatus.ended)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          icon: call.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          active: call.micMuted,
                          onTap: () => ref.read(callControllerProvider.notifier).toggleMic(),
                        ),
                        if (call.isVideo) ...[
                          _ControlButton(
                            icon: call.cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            active: call.cameraOff,
                            onTap: () => ref.read(callControllerProvider.notifier).toggleCamera(),
                          ),
                          _ControlButton(
                            icon: Icons.cameraswitch_rounded,
                            onTap: () => ref.read(callControllerProvider.notifier).switchCamera(),
                          ),
                        ] else
                          // Video calls skip this — the phone isn't held
                          // to the ear while looking at the screen, so
                          // the OS/WebRTC default (speaker) is already
                          // right; earpiece-vs-speaker is only ever a
                          // real choice on a voice call.
                          _ControlButton(
                            icon: call.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                            active: call.speakerOn,
                            onTap: () => ref.read(callControllerProvider.notifier).toggleSpeaker(),
                          ),
                        _ControlButton(
                          icon: Icons.call_end_rounded,
                          color: context.colors.danger,
                          large: true,
                          onTap: () => ref.read(callControllerProvider.notifier).endCall(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Whether the connected state's remote video surface should render.
  // call.status == connected is the sole "is this call live" check;
  // call.isVideo only decides whether a video surface exists at all —
  // a connected voice call is just as "live" as a connected video call,
  // it simply never has a video surface to show.
  bool _showRemoteVideo(CallState call) {
    return call.isVideo && call.status == CallStatus.connected && _remoteRenderer.srcObject != null;
  }

  String _statusLabel(CallState call) {
    return switch (call.status) {
      CallStatus.calling => 'Calling…',
      // A connected voice call has nothing left to wait on — it's live
      // the moment call:accept arrives, same as video's audio track.
      // "Connecting…" here is only meaningful for video while the
      // remote video frame hasn't arrived yet (see _showRemoteVideo).
      CallStatus.connected => call.isVideo ? 'Connecting…' : '',
      _ => '',
    };
  }
}

class _CenteredPeerInfo extends StatelessWidget {
  final CallState call;
  final String statusLabel;
  const _CenteredPeerInfo({required this.call, required this.statusLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(name: call.peerName, size: 120, photoUrl: call.peerPhotoUrl),
          const SizedBox(height: AppSpacing.lg),
          Text(call.peerName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
          if (statusLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(statusLabel, style: const TextStyle(color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool large;
  final Color? color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.large = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 64.0 : 52.0;
    final bg = color ?? (active ? Colors.white : Colors.white24);
    final iconColor = color != null ? Colors.white : (active ? Colors.black : Colors.white);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: large ? 30 : 24),
      ),
    );
  }
}
