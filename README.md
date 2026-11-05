# Bachs Flutter SDK (community)

[![Status: Community](https://img.shields.io/badge/status-community--preview-lightgrey)](https://docs.bachs.io/sdks/overview)

**Reusable Flutter integration for Bachs hosted checkout.** Merchant-independent, configurable, typed, testable, and designed to keep payment secrets off user devices.

> **Unofficial community project**. Not an official Bachs SDK. v0.2.0 is a developer preview. The v0.1.0 demo checkout worked in the author's iOS simulator, but v0.2.0 has not yet been compiled or sandbox-tested in this environment. Do not use this as a production payment implementation without reviewing, running tests, and completing sandbox + webhook verification.

## Why this exists

Version 0.1 was essentially one merchant's checkout demo. Version 0.2 is designed for **any** Flutter developer:

- A merchant can configure their **own** backend URL and app authentication, without modifying the package.
- They can select a different product, order ID, quantity, or reference through their own business/backend logic.
- They can implement their existing backend via injected functions **or** adopt a documented HTTP adapter.
- The Dart backend companion lets merchants configure their own Bachs **sandbox/live API key**, product cart or server-generated price, payment methods, redirects and webhook signing secret.
- The Flutter SDK launches a validated Bachs hosted checkout URL and allows an **authenticated merchant-backend** payment-status check, rather than trusting a browser redirect.
- Flutter unit tests, server unit tests, a multi-product example, and a reference server are included.

**Never put Bachs `sk_sandbox_...`, `sk_live_...` or `whsec_...` values in Flutter, assets, `--dart-define`, mobile secure storage, or a source repository.** Those values belong on an authenticated backend. Bachs requires this [officially](https://docs.bachs.io/sdks/overview).

## Packages

| Folder | What it does |
|---|---|
| `/` | `bachs_flutter`: merchant-independent Flutter client |
| `/server` | `bachs_server`: optional server-only Dart client + signed webhook verifier |
| `/example` | Flutter app demonstrating three merchant products and payment-status checks |
| `/server/bin/example_merchant_backend.dart` | **Local-only reference backend**, configured with environment variables and a catalog JSON file |
| `/docs` | backend protocol, architecture, security, presentation, release checklist |

## 1. Install in any Flutter application

While unpublished, use the **local path**:

```yaml
dependencies:
  bachs_flutter:
    path: ../bachs_flutter_sdk_v0.2.0
```

Later, once your own GitHub repository is published and reviewed:

```yaml
dependencies:
  bachs_flutter:
    git:
      url: https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
      ref: v0.2.0
```

No official pub.dev release is claimed. `publish_to: none` remains set until ownership, naming, README, licensing and CI are reviewed.

## 2. Option A: Use your existing authenticated backend (recommended)

There is **no required backend framework**. Use Firebase Functions, Laravel, NestJS, Django, .NET, Go, or anything else.

```dart
import 'package:bachs_flutter/bachs_flutter.dart';

final bachs = BachsFlutter(
  createSession: (request) async {
    // Call your OWN authenticated backend here.
    // Parse its safe checkout response with BachsCheckoutSession.fromJson(...)
    return BachsCheckoutSession.fromJson(await myApi.createBachsCheckout(
      request.toJson(),
    ));
  },
  verifyStatus: (orderId, checkoutId) async {
    // Your server checks its authenticated and verified order status.
    return BachsPaymentStatus.fromJson(await myApi.checkOrder(
      orderId: orderId, checkoutId: checkoutId,
    ));
  },
);

final session = await bachs.startCheckout(BachsCheckoutRequest(
  orderId: 'merchant-order-314',
  context: {'sku': 'annual-plan'},
));
// session.id holds the ID; checkout browser launched. No payment verified yet!

final status = await bachs.checkPayment(
  orderId: 'merchant-order-314', checkoutId: session.id,
);
if (status.isPaid) {
  // Display your backend-confirmed paid state. Backend does fulfillment.
}
```

**Pricing rule:** `context` is untrusted mobile input. Do NOT directly use it as the charge amount. Read the SKU/order/cart from a server-owned product database and validate ownership, price and currency before calling Bachs.

## 3. Option B: Use the included HTTP backend adapter

The adapter requires your **merchant backend URL**, not the Bachs API URL, and optionally a *user session token* (not a Bachs secret).

```dart
final backend = BachsBackendAdapter(
  baseUrl: Uri.parse('https://api.YOUR-COMPANY.com'),
  createPath: '/payments/bachs/checkout',
  statusPath: '/payments/bachs/status',
  tokenProvider: () async => auth.currentAccessToken,
);

final bachs = BachsFlutter(
  createSession: backend.createSession,
  verifyStatus: backend.checkStatus,
);

final checkout = await bachs.startCheckout(BachsCheckoutRequest(
  orderId: 'order_492', context: {'sku': 'team'},
));

// Later, for example when app resumes:
final status = await bachs.checkPayment(
  orderId: 'order_492', checkoutId: checkout.id,
);

// Close the adapter when no longer needed:
backend.close();
```

**Contract:** see [docs/BACKEND_CONTRACT.md](docs/BACKEND_CONTRACT.md). The default adapter expects:

- `POST /checkout` with `{"order_id":"...","context":{"sku":"..."}}` and returns Bachs public checkout session JSON.
- `GET /checkout-status?order_id=...&checkout_id=...` and returns `{"order_id":"...","checkout_id":"...","status":"pending|paid|failed|cancelled|expired"}`.

Both paths are configurable, and **existing APIs can bypass the adapter** using the functions in Option A.

### Optional ready-made Flutter button

```dart
BachsCheckoutButton(
  bachs: bachs,
  request: BachsCheckoutRequest(
    orderId: 'order_492', context: {'sku': 'team'},
  ),
  onCheckoutLaunched: (session) {
    // Save expected session.id; payment is still pending.
  },
  onError: (error) {
    // Show appropriate customer-friendly feedback.
  },
)
```

You can also use `bachs.startCheckout()` directly with any custom UI.

## 4. Set up your own Dart backend (optional)

Backend `pubspec.yaml`:

```yaml
dependencies:
  bachs_server:
    path: ../bachs_flutter_sdk_v0.2.0/server
```

Server Dart code:

```dart
import 'dart:io';
import 'package:bachs_server/bachs_server.dart';

final api = BachsClient(
  apiKey: Platform.environment['BACHS_API_KEY']!,
  environment: BachsEnvironment.sandbox, // switch explicitly for live
);

final session = await api.createCheckout(
  CreateCheckoutRequest(
    // Product-based: productCart: [BachsLineItem(productId: productId)],
    // OR server-calculated ad-hoc amount:
    pricing: const BachsPricing(currency: 'NGN', amount: '1000.00'),
    reference: 'order_492',
    metadata: {'order_id': 'order_492'},
    successUrl: Uri.parse('https://merchant.example/thanks'),
    cancelUrl: Uri.parse('https://merchant.example/cancel'),
  ),
  idempotencyKey: 'checkout-order_492',
);

// Send ONLY `session.toPublicJson()` to the authenticated Flutter caller.
// Store authoritative order -> checkout mapping server-side.
api.close();
```

All keys are supplied *at runtime* by **each merchant's own deployment**. This is not one shared Bachs account or hardcoded SDK-wide configuration. The Dart server client is **optional**; merchants can use Bachs' official Node/TypeScript SDK instead.

### Webhooks are SERVER-SIDE

```dart
final event = BachsWebhooks.constructEvent(
  rawBody: rawRequestBytes,
  headers: requestHeaders,
  secret: Platform.environment['BACHS_WEBHOOK_SECRET']!,
);
// Verify payment against order's expected amount/currency;
// atomically deduplicate event.id, persist results, fulfill exactly once.
```

Never send the signing secret to Flutter. This helper verifies the HMAC over the **raw bytes**, accepting Bachs signature V2 key rotation and the legacy signature format, with timestamp tolerance. See [Bachs webhook docs](https://docs.bachs.io/guides/webhooks/overview).

## 5. Return-to-app navigation

The app registers Universal Links (iOS) and Android App Links (or a compatible deep-link listener), and forwards incoming URLs to this SDK:

```dart
final bachs = BachsFlutter(
  createSession: backend.createSession,
  verifyStatus: backend.checkStatus,
  returnUrlMatcher: BachsReturnUrlMatcher(
    successUrl: Uri.parse('https://merchant.example/thanks'),
    cancelUrl: Uri.parse('https://merchant.example/cancel'),
  ),
);
final redirect = bachs.handleReturn(incomingUri);
if (redirect.kind == BachsReturnKind.successRedirect) {
  // UI may show 'Checking payment…'. Do NOT show 'Paid' yet.
  final status = await bachs.checkPayment(
    orderId: expectedOrderId,
    checkoutId: expectedCheckoutId,
  );
}
```

Bachs requires public HTTP(S) `success_url` / `cancel_url` values, not localhost. A successful redirect alone is never evidence of a paid transaction.

## 6. Run the example on your Mac

```bash
# project root
flutter pub get
(cd server && dart pub get)

# configure your OWN local merchant backend
cp server/.env.example server/.env
cp server/config/catalog.example.json server/config/catalog.json
# edit the environment file with sandbox credentials and your own public redirect URLs

# Terminal A (root directory)
cd server
set -a; source .env; set +a
dart run bin/example_merchant_backend.dart

# Terminal B (root directory)
cd example
flutter create --platforms=ios,android . # only if ios/android runners are missing
flutter pub get
flutter run --dart-define=BACHS_MERCHANT_BACKEND=http://127.0.0.1:8080
```

For the Android emulator use `http://10.0.2.2:8080`; opt-in HTTP loopback is supported **only** for simulator development. Production backends must be HTTPS. iOS Simulator may need a local networking ATS exception as described in [example/README.md](example/README.md).

Check with curl, using a new unique order ID:

```bash
curl -i -X POST http://127.0.0.1:8080/checkout \
  -H 'Content-Type: application/json' \
  -d '{"order_id":"order_demo_2026","context":{"sku":"starter"}}'
```

Expected: HTTP 201 with `checkout_id`, `checkout_url`, `status`. For test payments, Bachs CLI can forward signed webhooks to the local endpoint, then the example's **Check verified payment status** button shows the verified result.

**Reference backend warning:** It binds only to `127.0.0.1` and uses an in-memory order store with NO authentication, durable event deduplication, anti-replay business logic, or database persistence. It is a reference for the SDK contract, not a production payments backend.

## Test & quality gates

```bash
flutter pub get
flutter analyze
flutter test
(cd server && dart pub get && dart analyze && dart test)
```

A successful simulator checkout on v0.1.0 is evidence only for the old demo. Re-run these checks against v0.2.0 locally. See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).

## Resources

- [Migration from v0.1](docs/MIGRATING_FROM_V0_1.md)
- [Official Bachs checkout guide](https://docs.bachs.io/guides/checkout/checkout-sessions)
- [Official API keys](https://docs.bachs.io/developer-portal/api-keys)
- [Official webhooks](https://docs.bachs.io/guides/webhooks/overview)
- [Official SDK overview](https://docs.bachs.io/sdks/overview)

License: MIT. Contributions welcome, see `CONTRIBUTING.md`.
