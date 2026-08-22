/// Deep-link ("App Links") config for shared profile links.
///
/// ============================================================
/// NOT ACTIVE YET — this only takes effect once ALL of these exist:
/// ============================================================
///   1. A real domain you own (e.g. vivah.app), pointed at [host] below.
///   2. That domain hosting `/.well-known/assetlinks.json`, declaring
///      this app's package name (`com.shaadiclone.shaadi_clone` — see
///      android/app/build.gradle.kts) and its RELEASE signing
///      certificate's SHA-256 fingerprint. The app currently signs
///      release builds with the debug keystore (see build.gradle.kts's
///      TODO) — that must be replaced with a real release keystore
///      first, since assetlinks.json has to match whatever certificate
///      actually signs the APK real users install.
///   3. The domain also hosting a plain webpage at `/p/:code` for
///      anyone who opens the link without the app installed (a browser
///      falling back to a normal page, not the app, is standard OS
///      behavior for App Links when there's no match) — that page
///      should offer a Play Store link. A ready-to-deploy template for
///      both the assetlinks.json file and that landing page lives in
///      docs/deep-links/.
///   4. The app published on the Play Store (even an internal/closed
///      testing track works), so the landing page has somewhere to
///      send someone who doesn't have the app.
///   5. android/app/src/main/AndroidManifest.xml's App Links
///      intent-filter (already added, host=[host]) — update its
///      `android:host` value if you pick a different domain than
///      what's set here.
///
/// Until all of that is in place, sharing a profile still works exactly
/// as before (a plain-text summary with a searchable Profile ID) — see
/// [buildShareLink]'s doc.
class DeepLinkConfig {
  DeepLinkConfig._();

  /// CHANGE THIS to your real domain once you have one — must exactly
  /// match android:host in AndroidManifest.xml's App Links intent-filter.
  static const String host = 'vivah.example.com';

  static String profilePath(String profileCode) => '/p/$profileCode';

  /// The full shareable URL for a profile. Safe to use in share text even
  /// before the domain/App Links/Play Store setup above is complete — it
  /// just won't do anything special yet (a recipient's browser will 404
  /// or show nothing meaningful until the landing page in docs/deep-links/
  /// is actually deployed to [host]). The in-app Profile ID search still
  /// works as the real fallback in the meantime.
  static String buildShareLink(String profileCode) => 'https://$host${profilePath(profileCode)}';
}
