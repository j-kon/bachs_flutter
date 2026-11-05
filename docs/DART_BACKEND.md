# Optional Dart backend library

The `server/` package is independent of Flutter. Install it as a Git subpackage
in your trusted Dart service:

```yaml
dependencies:
  bachs_server:
    git:
      url: https://github.com/j-kon/bachs_flutter.git
      ref: main
      path: server
```

Use `package:bachs_server/bachs_server.dart` to access `BachsClient`,
`CreateCheckoutRequest`, `BachsPricing`, `BachsLineItem` and `BachsWebhooks`.
Read credentials from your server environment. Configure `BachsEnvironment.sandbox`
first; the client rejects an API key that does not match its environment.

The client creates and retrieves checkout sessions and verifies raw-body webhook
signatures (V2 and legacy). It does not supply your app's authentication, durable
order database or fulfillment workflow. Implement the [backend contract](BACKEND_CONTRACT.md),
including ownership checks, fixed server prices, durable idempotency and webhook
replay protection. Never trust a mobile-provided price or redirect outcome.

`bin/example_merchant_backend.dart` is a **localhost sandbox demonstration**.
It uses a local catalog and in-memory state; it is not suitable for public
production hosting. For a deployable starting point with authenticated users and
durable state, use the [Worker companion](SERVERLESS.md).

## Run the local demonstration

From the repository root:

```sh
cp server/.env.example server/.env
cp server/config/catalog.example.json server/config/catalog.json
```

Fill those ignored files with your sandbox configuration. Then:

```sh
cd server
set -a
source .env
set +a
dart pub get
dart run bin/example_merchant_backend.dart
```

The old local catalog expects `BachsCheckoutRequest(context: {'sku': ...})`.
The new shopping app uses `BachsPaymentRequest(productId: ...)` and the Worker
catalog instead. Choose the matching example; these are separate backend options.

For webhook verification call `BachsWebhooks.constructEvent` with the original
request bytes, headers and your server's signing secret before parsing or acting
on the event. Verify organization/order association, amounts and currencies;
store unique event IDs transactionally with state updates. Fulfill only once.
The library's signature check alone does not make event processing durable.

Validation commands and the tested toolchain are in [VALIDATION.md](VALIDATION.md).
