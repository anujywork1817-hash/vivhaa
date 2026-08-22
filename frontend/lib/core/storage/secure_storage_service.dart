import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps token persistence so repositories and [ApiClient] never touch
/// `flutter_secure_storage` directly.
class SecureStorageService {
  final FlutterSecureStorage _storage;
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  // Without this, Android falls back to a plain Keystore-wrapped-AES-key
  // scheme that's a known source of "logged out on next app open" reports
  // across the flutter_secure_storage ecosystem: certain OEM Keystore
  // implementations invalidate that key on things as ordinary as an
  // Android backup/restore pass or a routine security-patch update, and
  // the package's default AndroidOptions has no way to detect that
  // silently happened — reads just come back null next launch, which
  // looks identical to "never logged in" and forces the OTP screen again
  // even though nothing the user did was wrong. EncryptedSharedPreferences
  // is the package's own documented mitigation, backed by Android's more
  // resilient Jetpack Security library instead of a raw Keystore key.
  static const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: _androidOptions);

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> writeTokens({required String accessToken, required String refreshToken}) async {
    await writeAccessToken(accessToken);
    await writeRefreshToken(refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
