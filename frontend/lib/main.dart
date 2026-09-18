import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Modern Android (edge-to-edge enforced on API 35+) draws its own
  // background behind the system nav bar and ignores a solid
  // systemNavigationBarColor unless the app opts into edge-to-edge mode
  // itself — without this, app.dart's AnnotatedRegion trying to force
  // that bar white had no effect at all under dark mode. Edge-to-edge
  // plus a transparent system bar color lets the app's own (white)
  // BottomNavigationBar paint through underneath instead.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Push notifications are a secondary feature — if Firebase can't start
  // (missing or stale google-services.json, no Play Services on the
  // device), the app must still run. Only pushes are lost, and the
  // in-app WebSocket path still delivers everything live.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init failed, push notifications disabled: $e');
    }
  }

  runApp(const ProviderScope(child: ShaadiApp()));
}
