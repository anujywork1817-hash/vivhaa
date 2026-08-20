import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../core/config/google_auth_config.dart';

/// Thin wrapper around the real `google_sign_in` plugin — this talks to
/// Google's actual OAuth consent screen, not a mock. The account it
/// returns (id, email, display name, photo) is real; only the *session*
/// built from it downstream is client-side-only (see [AuthController]).
class GoogleAuthService {
  late final GoogleSignIn _googleSignIn;

  GoogleAuthService() {
    _googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile'],
      clientId: (kIsWeb && GoogleAuthConfig.isConfiguredForWeb)
          ? GoogleAuthConfig.webClientId
          : null,
      // Android/iOS: makes the native SDK mint an ID token audienced to
      // the backend's Web OAuth client, not the platform-auto-resolved
      // Android/iOS one — required for pkg/googleauth's aud-claim check
      // (GOOGLE_OAUTH_CLIENT_IDS) to accept it. Same Web client ID as
      // `clientId` above, just read for the other platforms — see
      // GoogleAuthConfig's doc comment for the full explanation.
      serverClientId: (!kIsWeb && GoogleAuthConfig.isConfiguredForServerAuth)
          ? GoogleAuthConfig.webClientId
          : null,
    );
  }

  /// Opens the Google account picker. Returns null if the user cancels.
  /// Throws if Google Sign-In isn't configured for this platform yet
  /// (missing OAuth client) so the caller can surface a clear error
  /// instead of a silent failure.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } on Exception catch (e) {
      throw GoogleAuthNotConfiguredException(e.toString());
    }
  }

  Future<void> signOut() => _googleSignIn.signOut();

  Future<void> disconnect() => _googleSignIn.disconnect();
}

class GoogleAuthNotConfiguredException implements Exception {
  final String details;
  const GoogleAuthNotConfiguredException(this.details);

  @override
  String toString() =>
      'Google Sign-In isn\'t configured for this platform yet: $details';
}

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) => GoogleAuthService());
