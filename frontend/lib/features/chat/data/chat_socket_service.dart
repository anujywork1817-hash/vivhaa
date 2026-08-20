import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/storage/secure_storage_service.dart';

/// Live connection to the backend's `/ws/chat` endpoint. One connection
/// per app session, shared by every open chat screen: [MessagesController]
/// filters the broadcast [events] stream down to the conversation it
/// cares about, and the conversations list invalidates itself on any
/// incoming message so unread counts stay live without polling.
///
/// Reconnects with a short fixed backoff on drop — good enough for a
/// mobile app that backgrounds/foregrounds a lot; not a full exponential
/// backoff / jitter strategy.
class ChatSocketService {
  final SecureStorageService _storage;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  bool _disposed = false;
  bool _connecting = false;

  ChatSocketService(this._storage);

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  /// Best-effort snapshot, not a guarantee — a connection can still die
  /// between this returning true and the next send (see [send]'s doc).
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    if (_disposed || _connecting || _channel != null) return;
    _connecting = true;
    try {
      final token = await _storage.readAccessToken();
      if (token == null) {
        // No token yet (e.g. called in a brief window right after login,
        // before it's written to secure storage) — previously this just
        // gave up silently with no retry scheduled, leaving the socket
        // dead for the rest of the session (no chat events would ever
        // arrive) until the app was restarted. Retry instead.
        _connecting = false;
        _scheduleReconnect();
        return;
      }

      final uri = Uri.parse('${ApiEndpoints.wsBaseUrl}/ws/chat?token=$token');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onError: (e) {
          debugPrint('ChatSocketService: connection error, reconnecting in 3s — $e');
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('ChatSocketService: connection closed '
              '(code=${channel.closeCode}, reason=${channel.closeReason}), reconnecting in 3s');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } finally {
      _connecting = false;
    }
  }

  /// Sends a raw JSON-encodable payload over the socket. Fire-and-forget:
  /// no delivery confirmation — fine for a chat message, which visibly
  /// never appears if dropped and the user can just retry.
  void send(Map<String, dynamic> payload) {
    if (_channel == null) {
      // Debug-only — this is exactly the failure mode ("looked like it
      // sent, nothing arrived") that's been hardest to diagnose from a
      // device we can't attach a debugger to; a logcat line makes it
      // provable at a glance instead of inferred from timing.
      debugPrint('ChatSocketService.send: DROPPED (_channel is null) — ${payload['type']}');
      return;
    }
    debugPrint('ChatSocketService.send: ${payload['type']}');
    _channel!.sink.add(jsonEncode(payload));
  }

  void _onData(dynamic raw) {
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      _eventsController.add(decoded);
    } catch (_) {
      // Malformed frame — ignore rather than crash the socket loop.
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    if (_disposed) return;
    Future.delayed(const Duration(seconds: 3), connect);
  }

  /// Tears down and re-establishes the connection unconditionally — unlike
  /// [connect], which no-ops if [_channel] is already set. A mobile OS can
  /// silently kill the underlying socket (screen lock, Doze, network
  /// switch) without ever firing this Dart-side stream's onError/onDone,
  /// leaving [_channel] non-null while the connection is actually dead —
  /// the server eventually notices via its ping/pong timeout and drops it,
  /// but the client never finds out and never reconnects on its own. Call
  /// this whenever the app resumes to the foreground so a zombie
  /// connection from before backgrounding doesn't stay silently dead for
  /// the rest of the session.
  void forceReconnect() {
    if (_disposed) return;
    _channel?.sink.close();
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    connect();
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.sink.close();
    _eventsController.close();
  }
}

/// Kept alive for the app session (not autoDispose) — every chat screen
/// shares this one socket rather than opening a new connection each time.
final chatSocketServiceProvider = Provider<ChatSocketService>((ref) {
  final service = ChatSocketService(ref.watch(secureStorageServiceProvider));
  service.connect();
  ref.onDispose(service.dispose);
  return service;
});
