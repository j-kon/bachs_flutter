# Bachs Flutter SDK

[![CI](https://github.com/j-kon/bachs_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/j-kon/bachs_flutter/actions/workflows/ci.yml)

## 1. What is Bachs Flutter SDK?

An **unofficial community SDK** for opening Bachs hosted checkout from Flutter and checking payment status through your merchant backend. Bachs collects payment details; your Flutter app never needs a Bachs secret key.

Not published on pub.dev. This project is under engineering review, not certified production-ready.

## 2. Features

- Open an existing hosted checkout URL with no custom backend.
- Create dynamic checkout with one endpoint configuration.
- Typed requests, sessions, errors and verified payment states.
- Sandbox and production checkout hosts with HTTPS validation.
- Loading button, status callbacks and verification on app resume.
- Return-link matching without treating redirects as payment confirmation.
- Optional merchant-owned Cloudflare Worker and Dart server library.
- Existing v0.2 provider-based integrations remain supported.

## 3. Installation

```yaml
dependencies:
  bachs_flutter:
    git:
      url: https://github.com/j-kon/bachs_flutter.git
      ref: main
```

Run `flutter pub get`, then import:

```dart
import 'package:bachs_flutter/bachs_flutter.dart';
```

Use `main` while reviewing. No verified release tag is recommended yet; pin a reviewed commit for reproducible builds. The SDK requires Dart >=3.3 and Flutter >=3.19; CI validates the versions documented in [validation](docs/VALIDATION.md). The example's app-links plugin has a newer SDK requirement.

## 4. Quick Start

Already have a checkout URL? Use [Opening Hosted Checkout](#5-opening-hosted-checkout).

For dynamic payments, configure your merchant endpoint once:

```dart
final bachs = BachsFlutter(
  config: BachsConfig(
    checkoutEndpoint: 'https://api.myapp.com/payments/checkout',
    // Use your signed-in user's short-lived token, never a Bachs key.
    tokenProvider: () async => userAccessToken,
  ),
);

final result = await bachs.pay(
  BachsPaymentRequest(orderId: 'order_123', productId: 'book', quantity: 1),
);
```

`userAccessToken` comes from your app's login provider. The endpoint must implement the contract below or use the optional starter. Product IDs and quantity are untrusted suggestions; prices belong on the server.

**`pay()` returns after checkout launch and a status request; it does not wait for the customer to finish.** The result normally has pending status. Keep it to check again on return. If the status service is unavailable, the session remains available and `result.verificationError` explains why it is unverified.

Call `bachs.close()` when its owning screen/service is disposed.

## 5. Opening Hosted Checkout

```dart
final bachs = BachsFlutter.hosted();
await bachs.openCheckoutUrl(
  Uri.parse('https://sandbox-checkout.bachs.io/c/YOUR_EXISTING_SESSION'),
);
bachs.close();
```

Supply a real, unexpired URL obtained from your merchant's existing checkout flow. This opens the browser only. It does not create a session, detect browser closure, verify a payment or fulfill an order. No Bachs credentials are needed in Flutter.

Allowed hosts include `checkout.bachs.io` and `sandbox-checkout.bachs.io`. Custom domains require an explicit `BachsCheckout(allowedHosts: {...})` override. HTTP, embedded credentials and nonstandard ports are rejected.

## 6. Dynamic Checkout Setup

`BachsConfig` needs `checkoutEndpoint`. By default the status URL is that endpoint followed by `-status`; set `statusEndpoint` explicitly if yours differs. Both must be on the same HTTPS origin to protect user tokens.

Your server exposes:

| Request | Response |
| --- | --- |
| `POST /payments/checkout` with `order_id` and optional `context` | `checkout_id`, `checkout_url`, `status: "open"`, optional `expires_at` |
| `GET /payments/checkout-status?order_id=...&checkout_id=...` | `order_id`, `checkout_id`, `status` |

Status values are `pending`, `paid`, `failed`, `cancelled`, or `expired`. The server authenticates the user, checks order ownership, sets prices, stores an idempotency key, and verifies signed Bachs webhooks. It must never return secrets to Flutter.

The [backend contract](docs/BACKEND_CONTRACT.md) has payloads and the [optional starter](docs/SERVERLESS.md) implements these routes without writing Bachs REST calls yourself. Existing backends can continue using `BachsFlutter(createSession: ..., verifyStatus: ...)` and `BachsBackendAdapter`.

## 7. Checkout Callbacks and Payment Verification

Use the ready-made button inside your screen:

```dart
BachsCheckoutButton(
  bachs: bachs,
  request: BachsPaymentRequest(orderId: 'order_123', productId: 'book'),
  label: 'Buy book',
  onPaymentResult: (result) {
    if (result.isPaid) {
      // Display confirmation. Your backend owns order fulfillment.
    }
  },
  onError: (error) {
    // Show a friendly retry message.
  },
)
```

The button disables duplicate taps, shows loading, then rechecks on app resume. A subsequent tap checks the same session instead of creating another. Use a new order ID (or widget key) for a new purchase. Customize `style`, `child`, `label` and `enabled`. Legacy `onCheckoutLaunched` remains launch-only.

With your own UI:

```dart
final latest = await bachs.verifyPayment(result);
if (latest.isPaid) {
  // Verified by your configured backend.
}
```

Configure `returnUrlMatcher` and pass incoming app links to `verifyReturn(uri, result)` to verify a return to the active checkout. A cancellation redirect is a navigation hint; a late payment can still be paid. Browser dismissal alone cannot establish cancellation. See [return-to-app setup](docs/RETURN_TO_APP.md) for Android App Links and iOS Universal Links. The example includes `app_links` wiring and lifecycle checks.

Session creation/launch failures throw `BachsSdkException` (`BachsCheckoutException` for browser launch). Network errors use codes such as `TIMEOUT`, `NETWORK` and `INVALID_RESPONSE`. An uncertain creation timeout must be retried with the same order ID and durable backend idempotency, not a new order.

## 8. Sandbox Testing

Start with a sandbox key **on your server only**, sandbox products and a sandbox webhook endpoint. The SDK accepts sandbox checkout URLs automatically. No live transactions are part of this project's automated tests.

Run the [shopping example](example/README.md) for product selection and simulated pending, paid, cancelled, expired and failed states. Simulated results are clearly labeled and never charge money. Switch to sandbox mode to use your real deployed backend and sign-in token.

For local backend development only, explicitly set `allowInsecureLoopback: true`. Remote HTTP endpoints remain prohibited. Real sandbox checkout and native return links require merchant credentials, deployed HTTPS pages and device testing; unit tests do not prove those flows.

## 9. Optional Backend Setup

Bachs' [authentication documentation](https://docs.bachs.io/authentication) requires server secret keys. As reviewed on 2026-11-05, we found no documented client-safe publishable key or mobile checkout-creation token. The [official checkout guide](https://docs.bachs.io/guides/checkout/checkout-sessions) requires server-side creation and webhook confirmation.

Choose either:

- **Cloudflare Worker + D1:** [deployment guide](docs/SERVERLESS.md). Configure your own Bachs sandbox credentials, a fixed catalog, return URLs and JWT issuer/JWKS/audience; deploy to your own account. Includes ownership checks, durable idempotency and signed webhook processing. Authentication setup remains required.
- **Dart backend:** use `server/` as a library in your existing authenticated service. [Dart guide](docs/DART_BACKEND.md). Its localhost reference executable is a sandbox demonstration, not a production server.

There is no shared service holding other merchants' secrets. The starter is optional and does not remove the need for authentication, durable payment state or server-side fulfillment.

## 10. Complete Example

The [example shopping app](example/) installs this SDK through Git and demonstrates the public API, product selection, pending verification, return links and friendly errors. See its README for running simulated and real sandbox modes.

A complete reusable integration function:

```dart
import 'package:bachs_flutter/bachs_flutter.dart';

Future<BachsPaymentResult> openOrderCheckout({
  required String orderId,
  required String userAccessToken,
}) async {
  final bachs = BachsFlutter(
    config: BachsConfig(
      checkoutEndpoint: 'https://api.myapp.com/payments/checkout',
      tokenProvider: () async => userAccessToken,
    ),
  );
  try {
    return await bachs.pay(BachsPaymentRequest(orderId: orderId));
  } finally {
    bachs.close();
  }
}
```

This returns the launched session and its current status. For a screen that verifies later, retain one SDK instance and the result until that screen is disposed, as the shopping example does.

## 11. Security

- Never place `sk_sandbox_`, `sk_live_`, or webhook signing secrets in Flutter code, assets, defines or storage. The SDK rejects recognized Bachs secret prefixes in configuration, tokens and request data as defense in depth.
- Never fulfill from launch callbacks, redirects or mobile state. Verify signatures and trusted order state on the server.
- Validate prices, currency, quantity and authenticated order ownership server-side. Persist idempotency and event deduplication.
- Review [security policy](SECURITY.md), [validation and audit scope](docs/VALIDATION.md), and [release checklist](docs/RELEASE_CHECKLIST.md) before deployment.

Automated scans and tests are evidence of specific checks, not a security certification or production-readiness guarantee.

## 12. License and Contributions

MIT — see [LICENSE](LICENSE). Contributions are welcome through [j-kon/bachs_flutter](https://github.com/j-kon/bachs_flutter); read [CONTRIBUTING.md](CONTRIBUTING.md). This SDK is not an official Bachs product and does not imply Bachs endorsement.
