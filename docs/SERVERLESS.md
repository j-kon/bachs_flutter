# Optional serverless checkout companion

`serverless/` is a merchant-owned Cloudflare Worker with D1 storage. Copy or deploy it into **your own Cloudflare account**, with your own Bachs keys and authentication provider. It is optional; Flutter can use any backend implementing the same contract. This repository supplies no hosted backend or shared merchant credentials.

The default is sandbox. Secrets belong in Worker secrets, never Flutter assets, source, `--dart-define`, browser JavaScript, or a distributable app. Flutter sends a short-lived signed user access token issued by your existing auth provider. The Worker verifies its signature against a configured HTTPS JWKS endpoint and requires matching issuer, audience, subject, expiry and issued-at. RS256 and ES256 are supported; opaque tokens and symmetric JWTs need a separate server-side adapter.

## Setup

Install Node 24 (Node >=22.13 is supported) and use a Cloudflare account with Workers and D1 available. From the repository:

```sh
cd serverless
npm ci
npm test
npm run check
npm run build
npx wrangler login
npx wrangler d1 create bachs-checkout
```

Put the returned database ID into `wrangler.toml`. Configure its `[vars]` values:

| Variable | Value |
| --- | --- |
| `AUTH_ISSUER` | Exact issuer of your application's access tokens |
| `AUTH_AUDIENCE` | Audience dedicated to your checkout API |
| `AUTH_JWKS_URL` | Your trusted auth provider's HTTPS public signing keys endpoint |
| `BACHS_ORGANIZATION_ID` | Your sandbox Bachs organization ID |
| `SUCCESS_URL`, `CANCEL_URL` | Your HTTPS return pages; neither proves payment |
| `ALLOWED_ORIGINS` | Comma-separated exact Flutter web origins; no wildcard |
| `CATALOG_JSON` | Merchant-owned product IDs, prices and maximum quantities |

Example catalog:

```json
{"demo_book":{"amount":"12.50","currency":"USD","max_quantity":5}}
```

These IDs are local catalog IDs, not Bachs `prod_` IDs. The starter creates a raw-amount, one-time checkout. It supports USD and NGN prices with exactly two decimals, quantities 1–99 capped by each product, and computes totals using integer arithmetic. No price, discount, currency, return URL or merchant identifier comes from the client. Adjust the catalog on the server to sell your own products. No Bachs product provisioning is required.

For local development, copy `.dev.vars.example` to `.dev.vars` and fill in your sandbox API key and webhook signing secret. That file is ignored by Git. For a deployment, enter secrets interactively:

```sh
npx wrangler secret put BACHS_SECRET_KEY
npx wrangler secret put BACHS_WEBHOOK_SECRET
npm run db:local
npm run dev
```

For your first remote deployment:

```sh
npm run db:remote
npm run deploy
```

These commands create resources, apply schema and deploy only when you run them; they have not been run against an account as part of preparing this starter. Cloudflare usage can incur charges.

Register `https://YOUR_WORKER_HOST/webhooks/bachs` in your Bachs **sandbox** Developer Portal. Subscribe to `collection.succeeded` and `checkout.expired`; `collection.failed` and `checkout.completed` can also be delivered but do not mark an order paid. Set `BACHS_WEBHOOK_SECRET` to this endpoint's secret. For local webhook forwarding, use Bachs CLI `bachs login --sandbox` then `bachs listen --forward-to localhost:8787/webhooks/bachs` and use the signing secret printed by that listener in `.dev.vars`.

## Flutter contract

Use a fresh UUID for each new logical order and persist it across retries. This sample creates and binds the order to the verified token's subject on its first request. It does not load an existing shopping-cart or inventory service. If your business already has orders, replace this creation policy with a lookup and authorization check against your order system.

```http
POST /checkout
Authorization: Bearer <current user access token>
Content-Type: application/json

{"order_id":"a-unique-order-uuid","context":{"product_id":"demo_book","quantity":1}}
```

```json
{"checkout_id":"chk_...","checkout_url":"https://checkout.bachs.io/c/...","status":"open","expires_at":"2026-11-05T12:30:00Z"}
```

Then query the trusted status endpoint using **both** IDs:

```http
GET /checkout-status?order_id=a-unique-order-uuid&checkout_id=chk_...
Authorization: Bearer <current user access token>
```

```json
{"order_id":"a-unique-order-uuid","checkout_id":"chk_...","status":"paid"}
```

The response status uses the app contract `pending | paid | failed | cancelled | expired`. This conservative starter emits `pending`, `paid`, and `expired`: a failed payment attempt may be retried in the same checkout, and closing a browser is not provider cancellation. `checkout.completed` alone does not prove money was collected. Status reads use D1's primary database and only report persisted verified webhook state; there is no browser-controlled fulfilment endpoint or direct API polling fallback. Lost webhooks require replay; the return page can keep showing pending until verification arrives.

Responses use `Cache-Control: no-store`. CORS permits only configured exact origins. Native apps send no Origin but still need a valid user token. CORS is not authentication.

## Durability and recovery

D1 persists the owner, immutable product/quantity, exact provider request, generated provider idempotency key, checkout mapping and verified event IDs. A unique order ID atomically reserves the create operation before calling Bachs. Concurrent calls cannot create a second provider checkout. Once ready, the same owner/cart returns the stored checkout. Other users get 404; changing the cart gets 409.

If a provider write times out, returns an error, returns malformed data, or its response cannot be saved, the reservation remains `creating`; the original request returns 503 and subsequent attempts return 409 `checkout_needs_reconciliation`. **Do not delete that row or start a new order to bypass it.** An upstream checkout might exist. No automatic retry is performed, including after restart or after Bachs' idempotency retention window.

An operator must inspect the order's stored request/key and Bachs request logs or dashboard, identify the original checkout by its reference, and retrieve that checkout using the server-side Bachs API. Verify its reference, amount, currency and URLs against the saved request before repairing the mapping and marking `phase` ready. Keep the same order owner and idempotency key. Only retry the exact original request with that same key when Bachs' documented recovery procedure confirms it is safe and still within its retention window. Never issue a fresh key for an uncertain payment. This starter deliberately does not automate manual reconciliation.

Webhook verification uses raw bytes, V2 HMAC-SHA256, a five-minute timestamp tolerance, Web Crypto digest verification and all `v1` signatures for rotation. It checks the configured organization, rejects Connect account events, and deduplicates by event ID. Status update and event marker commit in one D1 transaction. A webhook arriving before its checkout mapping returns 503 so Bachs can retry. A succeeded payment can advance an expired order to paid; paid never regresses. `ACCEPTED` payments are left pending for manual review because accepting less than requested is a business decision.

Before marking a `collection.succeeded` event paid, the Worker requires a match against the server-stored checkout ID, original order reference, charge amount and currency. A signed event with a different amount, currency or reference returns `503 payment_needs_reconciliation`, leaves the order pending, and is not recorded as a completed payment event. The operator must inspect the original Bachs charge and order before resolving it. In particular, a USD-priced checkout paid in a converted local currency requires an explicit FX-aware reconciliation process; this starter does **not** automatically mark it paid. For the first sandbox demonstration, use an NGN-priced checkout paid in NGN. These checks do not replace handling disputed, partially accepted, refunded or reversed payments.

## Verification and limits

`npm test` uses real RSA JWT signing/verification, HMAC and an in-memory SQLite database executing the production SQL through a small D1 adapter. Tests cover auth, audience, owner isolation, price tampering, immutable carts, create races, write ambiguity, webhook replay, body tampering, stale signatures, organization mismatch, transaction rollback and monotonic payment state. `npm run check` checks JavaScript with TypeScript; `npm run build` bundles a dry-run Worker.

Tests do not replace a sandbox payment on your deployed Worker. Before live use, complete an authenticated sandbox checkout, receive a real signed webhook, check status using the owning user, and verify another user cannot access it. The companion does not implement inventory, tax, shipping, subscriptions, refunds, disputes, recurring entitlements, fulfillment jobs, rate limits or automated reconciliation. Add account/IP rate limits in Cloudflare and quotas/business authorization for your app. Deliver goods using an idempotent backend job keyed by order ID after durable paid state, never the app's return URL. Monitor pending orders and webhook failures, replay missed events, and retain event IDs for the lifetime of associated orders.

Live use is deliberately gated. Use a separate Worker and D1 database; configure live organization and live webhook secret, set `BACHS_ENVIRONMENT="live"`, `ALLOW_LIVE_PAYMENTS="true"`, and a `sk_live_` secret. Check the catalog, returns, auth audience, rate limits, monitoring and recovery process for that deployment. The default sandbox worker cannot accept a live key.

## Primary references

Implementation checked against the following official documentation on 2026-11-05:

- [Bachs authentication and sandbox/live separation](https://docs.bachs.io/authentication)
- [Checkout sessions and raw amounts](https://docs.bachs.io/guides/checkout/checkout-sessions)
- [Bachs idempotency recovery](https://docs.bachs.io/guides/idempotency)
- [Webhook signature format, retries and deduplication](https://docs.bachs.io/guides/webhooks/overview)
- [Collection succeeded event and accepted/overpaid states](https://docs.bachs.io/guides/webhooks/events/collection-succeeded)
- [Cloudflare D1 prepared statements and transactional batch](https://developers.cloudflare.com/d1/worker-api/d1-database/)
- [jose remote JWKS resolver](https://github.com/panva/jose/blob/main/docs/jwks/remote/functions/createRemoteJWKSet.md)
