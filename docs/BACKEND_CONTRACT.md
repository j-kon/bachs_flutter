# Merchant backend contract (not the Bachs API)

This protocol is **between a merchant Flutter app and their own authenticated backend**. Developers can use any backend language. This is an *optional adapter protocol*, not a Bachs-specific API endpoint.

## 1. Create a checkout

`POST {merchantBaseUrl}{createPath}` (default `/checkout`)

Headers: `Content-Type: application/json`, optional `Authorization: Bearer {merchant-user-access-token}`.

Request:

```json
{
  "order_id": "order_492",
  "context": { "product_id": "notebook", "quantity": 1 }
}
```

The backend MUST authenticate the shopper, validate authorization to use this order, read its server-owned price and currency, set a durable idempotency key, create a session with Bachs using a merchant-owned **secret** key, store the mapping, then return only:

HTTP 201:

```json
{
  "checkout_id": "chk_123",
  "checkout_url": "https://checkout.bachs.io/c/abc",
  "status": "open",
  "expires_at": "2026-12-20T00:00:00Z"
}
```

**Do not accept a price from the app as authoritative.** `context.product_id` is only a hint, not permission to change prices. This allows dynamic products without having Flutter know a merchant's Bachs API key.

## 2. Retrieve the merchant-confirmed order status

`GET {merchantBaseUrl}{statusPath}?order_id=order_492&checkout_id=chk_123` (default `/checkout-status`).

HTTP 200:

```json
{
  "order_id": "order_492",
  "checkout_id": "chk_123",
  "status": "pending"
}
```

`status` must be exactly one of `pending`, `paid`, `failed`, `cancelled` or `expired`.

The backend MUST check that this user owns the order, that checkout_id is its stored ID, and that state derives from verified webhook events / reconciliation against Bachs. Use idempotent fulfillment, unique event IDs, expected amount and currency checks. The Flutter SDK verifies that response order/checkout IDs match its request and never marks an unverified browser redirect as paid.

## 3. Own backend adapters

Developers with existing endpoints can skip the HTTP adapter and implement `BachsSessionProvider` and `BachsStatusProvider` to map their own JSON into `BachsCheckoutSession` and `BachsPaymentStatus`.

## 4. Security requirements

- HTTPS for merchant APIs except explicitly opted-in loopback development.
- Merchant server authenticates end users and enforces order-level authorization on **both** endpoints.
- Keep Bachs `sk_...` and `whsec_...` ONLY in backend environment/secrets manager.
- Do not record success from redirect or browser launch; use signed Bachs webhooks.
- Make order creation idempotent and event processing idempotent and durable.
- Reconcile with Bachs on ambiguous writes; reject mismatched amount, currency and checkout ID.
- No customer PII or Bachs secrets in mobile logs or client-facing errors.

The legacy Dart localhost demo uses `context.sku`; the new Worker uses `product_id` and `quantity`. Keep one order ID per logical purchase. Treat a creation timeout as an uncertain write requiring durable idempotency/reconciliation. A status outage does not require another checkout.
