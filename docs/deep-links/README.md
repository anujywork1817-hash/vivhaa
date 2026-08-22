# Shared-profile deep links — setup checklist

The app is already wired to *receive* a link like `https://vivah.example.com/p/VV100042`
and open that profile directly (or fall back to a plain error screen if the code is
invalid). None of it is reachable from outside the app yet — this checklist is what's
left, all of it outside the codebase.

## 1. Get a domain

Anything you own works. Update these two places to match it exactly:

- `frontend/lib/core/config/deep_link_config.dart` — `host` constant.
- `frontend/android/app/src/main/AndroidManifest.xml` — the App Links intent-filter's
  `android:host` value.

(Both currently say `vivah.example.com` as a placeholder.)

## 2. Set up a real release signing keystore

The app currently signs release builds with the **debug** keystore
(`android/app/build.gradle.kts` has a `TODO` marking this). `assetlinks.json` below has
to declare the SHA-256 fingerprint of whatever certificate actually signs the APK real
users install, so this has to happen first — an assetlinks.json matching the debug key
would stop working the moment you switch to a real release key.

Once you have a release keystore, get its SHA-256 fingerprint:

```
keytool -list -v -keystore your-release-key.jks -alias your-key-alias | grep SHA256
```

## 3. Host `assetlinks.json`

Deploy `assetlinks.json` (in this folder) at exactly:

```
https://<your-domain>/.well-known/assetlinks.json
```

Must be served with `Content-Type: application/json`, over HTTPS, no redirects. Fill in
the SHA-256 fingerprint from step 2 before deploying — the placeholder in the file won't
verify.

Check it with Google's own tool once deployed:
https://developers.google.com/digital-asset-links/tools/generator

## 4. Publish the app

You need a live app for the fallback page to send someone to — even an internal/closed
testing track on the Play Store works. Once published, put the real Play Store URL into
`landing-page.html` (see the `PLAY_STORE_URL` placeholder near the top).

## 5. Host the landing page

Deploy `landing-page.html` (in this folder) so that a request to
`https://<your-domain>/p/<any-code>` serves it — most static hosts let you route
everything under `/p/*` to one file. This is what a recipient sees if they open the link
without the app installed (verified App Links open the app directly when it's
installed — this page is purely the no-app fallback).

## 6. Verify end to end

- Uninstall the app, tap a shared link → should open this landing page → Play Store link
  works.
- Install the app, tap a shared link → should open the app directly to that profile.
- `adb shell pm get-app-links com.shaadiclone.shaadi_clone` on a test device should show
  the domain as `verified`, not `legacy_failure`/`none` — if it's not verified, Android
  falls back to always asking the user which app to open the link with, defeating the
  point.
