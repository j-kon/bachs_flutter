# Multi-merchant Flutter example

This app demonstrates the **public package interface**, not the Bachs API key.
It supports three catalog SKUs so different products can be requested dynamically.
The merchant backend owns prices, credentials, customer authentication and webhooks.

## Start the reference backend

From the repository root:

```bash
cp server/.env.example server/.env
cp server/config/catalog.example.json server/config/catalog.json
# edit server/.env with your sandbox API key and PUBLIC redirect URLs
cd server
set -a; source .env; set +a
dart pub get
dart run bin/example_merchant_backend.dart
```

## Run iOS simulator

In a second terminal:

```bash
cd example
flutter create --platforms=ios,android . # if runner files don't exist
flutter pub get
flutter run --dart-define=BACHS_MERCHANT_BACKEND=http://127.0.0.1:8080
```

For an Android emulator replace 127.0.0.1 with 10.0.2.2. On iOS Simulator you may need an ATS local networking exception in Runner/Info.plist:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

Only opt in for **local development**. Production merchant backends should use HTTPS.

## Production integrators

- Set baseUrl to your own HTTPS backend.
- Configure `tokenProvider` to retrieve **your app user's short-lived auth token**.
- Replace the demo SKU with server-authenticated order IDs and server-stored prices.
- Host and verify Bachs webhook events on your backend.
- Configure actual Universal Links/App Links and forward incoming links to `bachs.handleReturn()`.
- Check paid status through your own backend. Browser launch or a success redirect is not proof of payment.

See the root README and docs/BACKEND_CONTRACT.md.
