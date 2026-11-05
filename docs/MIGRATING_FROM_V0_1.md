# Migrating from v0.1 to v0.2

v0.1's example app called a hardcoded local demo endpoint and used a fixed `BACHS_PRODUCT_ID`. v0.2 moves that policy out of the reusable Flutter package.

## What remains compatible

- `BachsCheckout().launch(session)` is still available for apps already creating secure sessions on their backend.
- `BachsCheckoutSession` and `BachsReturnUrlMatcher` remain available.
- `BachsClient` and `BachsWebhooks` remain server-only.

## What is new

1. `BachsFlutter` accepts **merchant-provided** `createSession` and `verifyStatus` functions.
2. `BachsBackendAdapter` optionally implements a simple merchant checkout/status HTTP contract.
3. `BachsCheckoutRequest(orderId: ..., context: ...)` carries dynamic order parameters without exposing merchant pricing policy.
4. `BachsCheckoutButton` is a convenience widget.
5. The example app and merchant backend now use SKU catalog JSON and `BACHS_MERCHANT_BACKEND` instead of a fixed product.

## Existing checkout demo

The old `server/bin/server.dart` command is now an alias for the **new local reference backend**, which expects `server/config/catalog.json`. Copy it from the example file. This change is intentional: merchant configuration belongs outside the public SDK.

Environment keys you already have can stay in your private `server/.env`. The new reference backend uses `BACHS_API_KEY`, optional `BACHS_WEBHOOK_SECRET`, `BACHS_SUCCESS_URL`, `BACHS_CANCEL_URL`, plus an optional catalog file path, not `BACHS_PRODUCT_ID`.

## Preserve private keys

If updating an existing directory, **back it up first** and do not delete or overwrite `server/.env`. The ZIP never includes real credentials.
