# Public SDK architecture

```text
Merchant Flutter app                Merchant-authenticated backend             Bachs API
       |                                           |                              |
       | bachs.startCheckout(orderId, context)     |                              |
       |---- POST /checkout ---------------------->|                              |
       |         [shopper access token]            | price from server DB         |
       |                                           |-- create checkout (sk_) --->|
       |                                           |<-- chk_... and checkout URL -|
       |<--- checkout_url and checkout_id ---------|                              |
       |---- external browser --> Bachs hosted checkout --------------------->   |
       |                                           |<--- signed webhook ---------|
       |                                           | raw-byte HMAC verification   |
       |                                           | validate amount / currency   |
       |                                           | store event, fulfill once    |
       |---- GET /checkout-status ---------------->| read verified order state    |
       |<--- pending/paid/failed ------------------|                              |
```

## Public package

The simplest entry points are `BachsFlutter.hosted()` for an existing URL and `BachsFlutter(config: BachsConfig(...))` for dynamic checkout. `pay` launches and requests current status; `verifyPayment` and `verifyReturn` refresh it without recreating checkout. A `BachsPaymentResult` keeps the session even when status verification fails.

- `BachsCheckoutRequest` carries the developer's order ID and an arbitrary **untrusted** context map.
- `BachsFlutter` composes a `BachsSessionProvider`, optional `BachsStatusProvider`, `BachsCheckout` URL launcher, and optional `BachsReturnUrlMatcher`.
- `BachsBackendAdapter` is optional: base URL, configurable paths, optional short-lived user token provider, injected HTTP client, timeout and opt-in loopback HTTP.
- `BachsCheckoutButton` is an optional Flutter widget with loading and error callbacks.
- `BachsPaymentStatus` exposes `pending/paid/failed/cancelled/expired`, sourced exclusively from the merchant's backend.
- No Bachs API keys, no Bachs webhook signing secrets, no merchant account global singleton.

## Server companion

- `BachsClient` server-side checkout/product/payment API; sandbox/live isolation; idempotent creation; HTTP transport injection for tests.
- `CreateCheckoutRequest` supports server-controlled product carts, price overrides, ad hoc pricing, customer, payment method corridors, customer creation, metadata and redirects.
- `BachsWebhooks.constructEvent` validates raw-byte signatures and timestamps, including V2 multiple rotation signatures.
- The local reference server demonstrates an optional adapter contract. Real merchants can instead use the official Node/TypeScript Bachs SDK or any other backend.

## Scope and limitations

- PCI card data collection or embedded native card fields.
- Automatically installing OS deep-link association for an unrelated merchant.
- Arbitrary payouts/refunds from Flutter devices using privileged keys.
- Automatic order fulfillment or consumer-facing transaction history. The optional Worker persists and deduplicates events, but fulfillment jobs remain merchant-owned.
- Hardcoding one merchant's API credentials/product IDs into the SDK.

## Optional serverless deployment

The [Cloudflare Worker](SERVERLESS.md) implements authenticated checkout and status routes, fixed server pricing, D1 order reservations, immutable carts, durable webhook deduplication and transactionally recorded payment state. It defaults to sandbox. It is a starter for a single merchant deployment, not a shared secrets service.
