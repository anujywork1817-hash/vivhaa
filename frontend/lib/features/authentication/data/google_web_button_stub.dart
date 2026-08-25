import 'package:flutter/widgets.dart';

/// Non-web platforms never render Google's own button — the custom
/// "Continue with Google" button plus the imperative `signIn()` call
/// works fine there (only web requires the GIS-rendered button to get an
/// ID token — see google_web_button_web.dart).
Widget? renderGoogleWebButton() => null;
