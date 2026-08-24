import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';

/// Maps a push's raw `data` payload (backend event `type` + whatever ids
/// it carried, e.g. `interest_id`/`sender_user_id` — see
/// cmd/notification/main.go's pushData) to a route to navigate to when
/// the notification is tapped. Mirrors
/// notifications_screen.dart's notificationTargetRoute, but works off the
/// FCM string payload directly rather than an AppNotification, since a
/// tapped push (background/killed app) never goes through the in-app
/// notifications list at all.
String? _routeForPushData(Map<String, dynamic> data) {
  switch (data['type']) {
    case 'interest_received':
    case 'interest_reminder':
    case 'match':
      final interestId = data['interest_id'] as String?;
      return interestId == null ? null : AppRoutes.interestDecisionPath(interestId);
    case 'new_message':
    case 'contact_request':
    case 'contact_accepted':
    case 'contact_declined':
      final partnerUserId = data['sender_user_id'] as String?;
      return partnerUserId == null ? null : AppRoutes.chatWindowPath(partnerUserId);
    default:
      return null;
  }
}

/// Must match the channel id the backend sets on every push
/// (pkg/firebase/fcm.go). Android 8+ silently drops a notification whose
/// channel doesn't exist, so the channel is created here at startup rather
/// than lazily on first receipt.
const _channelId = 'vivaha_default';

const _channel = AndroidNotificationChannel(
  _channelId,
  'Vivah notifications',
  description: 'Interests and messages',
  importance: Importance.high,
);

/// Handles FCM registration and display.
///
/// Two delivery paths matter and behave differently:
///  * **background / terminated** — Android draws the notification itself
///    from the `notification` payload; the app isn't involved.
///  * **foreground** — Android suppresses it, so it has to be drawn
///    manually via flutter_local_notifications or the user sees nothing.
class PushNotificationService {
  final ApiClient _client;
  final Ref _ref;
  final _local = FlutterLocalNotificationsPlugin();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialised = false;

  PushNotificationService(this._client, this._ref);

  /// Sets up channels and listeners. Safe to call more than once.
  Future<void> initialise() async {
    if (_initialised || kIsWeb) return;
    _initialised = true;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);

    _foregroundSub ??= FirebaseMessaging.onMessage.listen(_showForeground);

    // Tapped while backgrounded (app process alive, just not foreground).
    _openedAppSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_navigateTo);

    // Tapped from fully killed — the app cold-starts and the message that
    // launched it is handed back here rather than through the stream
    // above, which only fires for messages received *after* this
    // listener was attached. Fire-and-forget: by the time this resolves,
    // the router built in ShaadiApp's first frame already exists (this
    // runs from AppShell.initState, well after the router provider is
    // first read), so there's a real GoRouter to push onto.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _navigateTo(message);
    });

    // FCM rotates tokens (app restore, reinstall, data clear). Without
    // re-registering, the backend keeps pushing to a dead token and the
    // user silently stops receiving notifications.
    _tokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_sendToken);
  }

  void _navigateTo(RemoteMessage message) {
    final route = _routeForPushData(message.data);
    if (route != null) _ref.read(appRouterProvider).push(route);
  }

  /// Requests permission and registers this device against the signed-in
  /// account. Call after login, once an auth token exists — the register
  /// endpoint is authenticated.
  Future<void> registerDevice() async {
    if (kIsWeb) return;
    await initialise();

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // Nothing to register: the user declined, and any previously stored
      // token for this device would now be undeliverable anyway.
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _sendToken(token);
  }

  /// Drops this device's token on sign-out so the next person to use the
  /// phone doesn't receive the previous account's notifications.
  Future<void> unregisterDevice() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _client.dio.delete(ApiEndpoints.deviceToken, data: {'token': token});
    } catch (_) {
      // Best effort — sign-out must not be blocked by a failed cleanup.
      // The backend also reassigns a token on next registration, so a
      // missed unregister self-corrects when someone else signs in.
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      await _client.dio.post(
        ApiEndpoints.deviceToken,
        data: {'token': token, 'platform': 'android'},
      );
    } catch (_) {
      // Registration is retried on the next launch and on token refresh;
      // a transient failure here shouldn't surface to the user.
    }
  }

  void _showForeground(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Vivah notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref.watch(apiClientProvider), ref);
  ref.onDispose(service.dispose);
  return service;
});
