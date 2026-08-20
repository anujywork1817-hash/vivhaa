import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
