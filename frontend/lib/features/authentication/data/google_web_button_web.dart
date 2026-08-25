import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Renders Google's own GIS Sign-In button widget.
///
/// Google's Identity Services deliberately withholds the ID token from an
/// imperative, custom-button-triggered `signIn()` call on web — an ID
/// token is only ever issued through a click on Google's own rendered
/// button (a security/anti-abuse policy, not a bug). This is why the app's
/// custom-styled "Continue with Google" button (which works fine on
/// Android/iOS, where the native SDK has no such restriction) got a null
/// `idToken` on web. The resulting sign-in still has to go through the
/// same `GoogleSignIn` instance's `onCurrentUserChanged` stream — see
/// GoogleAuthService.onCurrentUserChanged, which this button's result
/// feeds automatically via the platform's `userDataEvents`.
Widget? renderGoogleWebButton() {
  return web.renderButton(
    configuration: web.GSIButtonConfiguration(
      type: web.GSIButtonType.standard,
      theme: web.GSIButtonTheme.filledBlue,
      size: web.GSIButtonSize.large,
      shape: web.GSIButtonShape.pill,
      text: web.GSIButtonText.continueWith,
      logoAlignment: web.GSIButtonLogoAlignment.left,
    ),
  );
}
