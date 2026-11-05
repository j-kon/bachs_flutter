# Little Goods — Bachs sandbox shop

A small Flutter shopping app consuming the SDK through its public Git dependency:

```yaml
bachs_flutter:
  git:
    url: https://github.com/j-kon/bachs_flutter.git
    ref: main
```

## Run without a backend

Use a Flutter SDK with Dart 3.12 or newer. From this directory:

```bash
flutter pub get
flutter run
```

The default is **SIMULATED DEMO**. Select a notebook, mug or tote, change quantity,
and press **Pay with Bachs**. Pending, paid, cancelled, failed, expired and network-outage
controls run the real SDK with injected session/status providers and a no-op
browser launcher. No requests are made, no payment page opens and no money moves.
Product selection stays locked throughout a checkout. After a terminal result,
**Shop again** unlocks it. Pending checkouts remain available for status retries.

```bash
flutter analyze
flutter test
```

For unpublished SDK development only, create an ignored `pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  bachs_flutter:
    path: ..
```

Remove this override and run `flutter pub get` to test the published Git branch.
Use `flutter pub upgrade bachs_flutter` to move a previously locked checkout to the latest Git main. The Git branch must include the new `BachsConfig` and `BachsPaymentRequest` API.
Do not commit a lockfile resolved with the local override as a Git integration
verification. Pin a reviewed commit instead of `main` in a deployed application.

## Live sandbox

Provide your merchant's HTTPS sandbox backend endpoint. The SDK derives the
status endpoint by appending `-status`; supply `statusEndpoint` in `BachsConfig`
if your merchant uses another route.

```bash
flutter run \
  --dart-define=BACHS_CHECKOUT_ENDPOINT=https://sandbox.your-shop.com/checkout \
  --dart-define=BACHS_RETURN_BASE=https://sandbox.your-shop.com/pay
```

Enter an existing **merchant-created sandbox order ID** and the current user's
short-lived login token in the app. The token is held in memory, obscured in the
UI and never saved or logged. For a real app, replace this field's token provider
with your authenticated session's refresh-aware token callback. Never enter a
Bachs API key, webhook secret or merchant secret here, in Dart defines or in
client storage.

The backend authenticates the user, verifies order ownership, validates the
selected product and quantity, and owns prices. The displayed catalog is only
illustrative: create matching sandbox products/orders on your backend. The optional Worker ships with these three local catalog IDs and binds a fresh UUID order ID to the first authenticated buyer; existing backends should issue their own order IDs. See
[the backend contract](../docs/BACKEND_CONTRACT.md). Pressing Pay calls
`sdk.pay(BachsPaymentRequest(...))` and opens the returned hosted checkout URL.
An opened browser is never displayed as a paid order. **Check status**, app
resume and matching return links request backend verification. Only a verified
`paid` result renders confirmation in live mode. Errors retain the active order
for retries; do not create another order to recover a status-check outage.

An optional `BACHS_HOSTED_CHECKOUT_URL` define exposes **Open existing sandbox
checkout URL**, demonstrating `sdk.openCheckoutUrl(Uri)`. This URL must come from
your server and use a trusted HTTPS checkout host. The URL-only flow cannot
verify or claim payment; use the order-based flow for completion handling. Do
not distribute private customer checkout URLs in a production build.

## Return to the app

The app instantiates `AppLinks` before `runApp` and listens to `uriLinkStream`
(initial and subsequent links). It calls `sdk.verifyReturn(uri, activeResult)`;
redirect query parameters never establish payment. It also retries verification
when the application resumes. See the official [app_links usage](https://pub.dev/packages/app_links)
and platform setup: [Android](https://github.com/llfbandit/app_links/blob/main/doc/README_android.md),
[iOS](https://github.com/llfbandit/app_links/blob/main/doc/README_ios.md).

Configure the merchant's actual return URLs to match
`https://sandbox.your-shop.com/pay/success` and `/pay/cancel`. The default
`shop.example.com` is a placeholder. App/Universal Links require a domain you own.
Android, iOS and web runners are included. Deep linking through Flutter is disabled for app_links; add your own domain configuration below:

### Android

Inside the MainActivity element of `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="sandbox.your-shop.com" android:pathPrefix="/pay/" />
</intent-filter>
```

Publish the domain's `/.well-known/assetlinks.json` with the runner package name
and SHA-256 signing certificate fingerprint. Follow [Flutter's App Links guide](https://docs.flutter.dev/cookbook/navigation/set-up-app-links).
Ensure the main manifest has Internet permission for release sandbox builds.
Test a matching link while checkout is pending:

```bash
adb shell am start -a android.intent.action.VIEW -d 'https://sandbox.your-shop.com/pay/success'
```

### iOS

In `ios/Runner/Info.plist` add:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

Enable Associated Domains for the Runner target with
`applinks:sandbox.your-shop.com`. Publish
`/.well-known/apple-app-site-association` containing your team ID, bundle ID and
`/pay/*` path association. Follow [Flutter's Universal Links guide](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)
and the app_links version 7 lifecycle setup linked in its iOS documentation.
Test on a simulator/device with the actual associated domain:

```bash
xcrun simctl openurl booted 'https://sandbox.your-shop.com/pay/success'
```

This example keeps the active checkout in memory. A cold start after process
termination shows a restore-order message and never accepts redirect data as
proof of payment. A production merchant app must restore authenticated orders
and checkout IDs from its backend/account history before verification. Desktop
native link registration and production order recovery are outside this sample.
