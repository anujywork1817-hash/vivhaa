import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaadi_clone/app/app.dart';
import 'package:shaadi_clone/core/storage/secure_storage_service.dart';

/// Never touches the flutter_secure_storage platform channel — the real
/// [SecureStorageService] does, and the test binding has no handler
/// registered for it, which is why this test needs a fake in the first
/// place (BUG-F01): without overriding secureStorageServiceProvider, the
/// splash screen's SplashScreen._resume() call to readAccessToken() either
/// throws (MissingPluginException) or hangs, and either way the app never
/// reaches the auth gate this test asserts on.
class _FakeSecureStorageService extends SecureStorageService {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

void main() {
  testWidgets('App boots through splash to the sign-up gate', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorageService()),
      ],
      child: const ShaadiApp(),
    ));

    // Splash renders first.
    await tester.pump();
    expect(find.text('Vivaha'), findsOneWidget);

    // Auto-advances to the sign-up/login gate.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Sign Up with Email'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('SplashScreen falls back to the auth gate when secure storage fails (BUG-F01/M01)',
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(_ThrowingSecureStorageService()),
      ],
      child: const ShaadiApp(),
    ));

    await tester.pump();
    expect(find.text('Vivaha'), findsOneWidget);

    // Before the fix, a thrown PlatformException here left _resume()
    // never calling context.go(...) at all — the app would still be
    // stuck on the splash screen after this pump, not on the auth gate.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Sign Up with Email'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}

/// Simulates the real-world failure mode this bug fix targets: a
/// flutter_secure_storage read that throws (e.g. BAD_DECRYPT after an
/// Android backup/restore corrupts the encrypted prefs file).
class _ThrowingSecureStorageService extends SecureStorageService {
  @override
  Future<String?> readAccessToken() async =>
      throw Exception('simulated secure storage failure (BAD_DECRYPT)');
}
