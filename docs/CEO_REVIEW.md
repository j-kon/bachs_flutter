# Bachs Flutter SDK: engineering review brief

**Proposal:** An independently developed community Flutter integration that helps Bachs merchants accept payments in Flutter applications while keeping Bachs API secrets on their own servers.

## Demonstrate the engineering, not just a screenshot

1. Show the **public API** in `README.md` and `lib/src/checkout_flow.dart`: dynamic backend, dynamic order context, no hardcoded merchant account.
2. Launch the `example/` iOS sample with three separate merchant catalog prices, all using the SAME SDK build.
3. Show the `server/` secret-only Bachs client supporting both `product_cart` and `pricing` on the trusted backend.
4. Demonstrate mock HTTP tests proving the app sends user auth only to its own backend and never includes a Bachs secret.
5. Show how a webhook is HMAC-verified, deduplicated and checked against server-stored amount/currency before the local demo calls an order paid (note: in-memory only).
6. Complete a real sandbox checkout and record webhook receipt. Explain what is still pending before a production release.

## Request to the Bachs engineering team

- API/SDK contract review, particularly return URLs and webhook event semantics.
- Permission to use the company name and visual branding in the package.
- Guidance on package naming, versioning and contribution workflow.
- Opportunities to collaborate on a production-quality, officially maintained Flutter integration.

## What not to claim

- This is **not** official or approved by Bachs.
- Unit tests written do not mean Flutter or Dart tests were executed in this environment.
- The local example server is **not** production-ready.
- A checkout redirect is **not** proof of successful payment.
