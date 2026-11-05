## 0.3.0

- Add BachsConfig endpoint integration, BachsPaymentRequest and BachsPaymentResult.
- Add pay, verifyPayment, verifyReturn and existing hosted URL launch.
- Accept official sandbox checkout host; reject secrets in mobile requests/tokens.
- Preserve launched sessions on verification outages and verify button state on resume.
- Add optional authenticated Cloudflare Worker/D1 starter and runnable Git-installed shop.
- Enforce formatting, analysis, tests, backend compilation and dependency/security CI checks.
- Preserve v0.2 custom-provider APIs; document return navigation and deployment limits.

# Changelog

## 0.2.0 (community developer preview)

- Added merchant-independent Flutter `BachsFlutter` orchestrator.
- Added configurable `BachsBackendAdapter` with per-developer base URL, endpoint paths and user-token provider.
- Added runtime order context and merchant-backed typed payment status checks.
- Added reusable Flutter `BachsCheckoutButton`.
- Added dynamic 3-product demo catalog; no single fixed product inside the SDK.
- Added configurable localhost-only merchant backend, signed event checks and status endpoint.
- Expanded server checkout options: product price overrides, payment corridors, billing currency, customer creation.
- Added API contract, architecture, security guidance, engineering review and release checklist.
- Added unit/widget tests. **New version not yet run through Dart/Flutter locally.**

## 0.1.0

- Initial hosted checkout launcher and server companion.
- Local sandbox checkout was subsequently confirmed working on an iOS simulator.
