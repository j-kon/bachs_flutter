# Restored Bachs Flutter SDK v0.2.0

This archive combines the **original v0.2.0 SDK source** with the **two-file analyzer/syntax correction** supplied afterward:

- `server/bin/example_merchant_backend.dart`
- `lib/src/return_url.dart`

The original user reported clean `flutter analyze` and `dart analyze` plus **16/16 Flutter** and **15/15 Dart server** unit tests after applying this patch on macOS. This recovered archive has not been recompiled in the packaging environment. Re-run the checks locally before publishing.

## 1. Restore and validate

Unzip this file within `~/Developer/jaykon/`. It creates the directory `bachs_flutter_sdk_v0.2.0`.

```sh
cd ~/Developer/jaykon/bachs_flutter_sdk_v0.2.0
flutter pub get
flutter analyze
flutter test
cd server
dart pub get
dart analyze
dart test
```

## 2. Run the reference merchant backend

The reference server is **for localhost sandbox testing only**, not a production payment server. Replace the example values and keep secrets off GitHub and away from Flutter assets.

```sh
cd ~/Developer/jaykon/bachs_flutter_sdk_v0.2.0
cp server/.env.example server/.env
cp server/config/catalog.example.json server/config/catalog.json
# Edit server/.env with sandbox credentials and your public HTTPS return URLs
cd server
set -a
source .env
set +a
dart run bin/example_merchant_backend.dart
```

On a second terminal:

```sh
cd ~/Developer/jaykon/bachs_flutter_sdk_v0.2.0/example
flutter create --platforms=ios,android .  # only if the native runner directories are missing
flutter pub get
flutter run --dart-define=BACHS_MERCHANT_BACKEND=http://127.0.0.1:8080
```

The iOS simulator may require the local networking exception described in `example/README.md`.

## 3. Connect a completely separate Flutter app

Put both folders beside each other:

```
~/Developer/jaykon/bachs_flutter_sdk_v0.2.0/
~/Developer/jaykon/bachs_payments_showcase/
```

In the showcase app's `pubspec.yaml`:

```yaml
dependencies:
  bachs_flutter:
    path: ../bachs_flutter_sdk_v0.2.0
```

The SDK is independent of any single merchant. The **Dart backend** stores API keys, owns pricing and verifies webhooks; Flutter only calls the merchant backend. See `README.md` and `docs/BACKEND_CONTRACT.md`.

## 4. Before sharing publicly

- Run `git status --short` and review `git ls-files` for secret files and build artifacts.
- Double-check `.env` and `server/config/catalog.json` are ignored.
- Never embed Bachs API keys or `whsec_` secrets in the Flutter app.
- Confirm the package installs in the separate app and can create a sandbox checkout.
- Complete signed webhook verification and payment-state tests before claiming production readiness.
