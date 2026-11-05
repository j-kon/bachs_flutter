# Release checklist

## Required before proposing production adoption

- [ ] Run `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` then `flutter test` at the root.
- [ ] Under `server/` run `dart format --output=none --set-exit-if-changed lib test bin`, `dart analyze`, and `dart test`.
- [ ] Run package/example app on iOS Simulator and Android Emulator.
- [ ] Test with two distinct sandbox accounts to prove config separation and no shared keys.
- [ ] Exercise raw price and product-cart checkouts in Bachs sandbox.
- [ ] Exercise V2 webhook signature, rotated signing secrets, invalid signatures, duplicate events and out-of-order events.
- [ ] Confirm status is pending until signed webhook / server reconciliation; never derive paid from redirect.
- [ ] Demonstrate normal return, cancellation, app background/foreground, expired checkout, failed network.
- [ ] Independently review Bachs API endpoint names and all request/response fields against current documentation.
- [ ] Hardening: authenticated orders, database transactions, idempotency, persistent event dedupe, replay/amount/currency protections, order ownership.
- [ ] Review README and examples for credentials, contact information and accidental secrets.
- [ ] Confirm current package name and any required Bachs trademark approval before pub.dev publication.
- [ ] Update GitHub Actions CI to run static analysis and tests on supported SDK versions, and publish changelog/release notes.
- [ ] Review BSD/MIT dependencies, code of conduct and security disclosure policy.

## Development-only known limitations

The bundled local backend has no authentication, database, persistence, durable deduplication or retry-safe long-term processing. It binds only to loopback. It MUST NOT be deployed as a payment processor.

The separate Worker has authenticated ownership and durable D1 state, but still requires deployment-specific rate limits, monitoring, reconciliation and idempotent fulfillment. Follow [SERVERLESS.md](SERVERLESS.md); passing CI does not complete this production checklist.
