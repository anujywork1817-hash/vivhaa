/// Google OAuth client configuration.
///
/// [webClientId] is the **Web application** OAuth 2.0 Client ID from
/// Google Cloud Console (APIs & Services → Credentials — the one labeled
/// "Web client (auto created by Google Service)", not any Android/iOS
/// client). It's used two ways, both requiring this same Web client ID:
///  * on Flutter web, as `GoogleSignIn`'s `clientId`;
///  * on Android/iOS, as `GoogleSignIn`'s `serverClientId` — this is what
///    makes the native SDK mint an ID token audienced to your *backend's*
///    OAuth client instead of the platform-auto-resolved Android/iOS one,
///    which is required for the backend to accept it: `pkg/googleauth`
///    checks the token's `aud` claim against `GOOGLE_OAUTH_CLIENT_IDS`,
///    and that list is the Web client ID, not the Android one. Android
///    still separately needs its own OAuth client registered (by package
///    name + signing fingerprint) in the same Cloud project for the
///    sign-in *picker* itself to work — that's a Google Cloud Console
///    registration, not something set in this file.
///
/// Hardcoded rather than passed via --dart-define: OAuth client IDs are
/// public identifiers, not secrets (they identify the app; they don't
/// grant access on their own — the security boundary is the Android
/// signing fingerprint plus the backend's token verification), so a
/// plain `flutter run`/`flutter build apk` must work with no extra flags.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  static const String webClientId =
      '879856026168-a82vq1aco24pr25gq540m5qe5e7rc4eq.apps.googleusercontent.com';

  static bool get isConfiguredForWeb => webClientId.isNotEmpty;

  /// True once a Web client ID has been supplied — same flag, read for
  /// its "is this actually set" meaning rather than its "for web" name,
  /// since serverClientId on native platforms needs the exact same check.
  static bool get isConfiguredForServerAuth => webClientId.isNotEmpty;
}
