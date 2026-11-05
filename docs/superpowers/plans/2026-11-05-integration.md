# Easy integration implementation plan

> Execute with focused parallel agents for independent CI/serverless/example work; root implements SDK and reviews integration.

**Goal:** Make the unofficial SDK installable in minutes without putting payment secrets in mobile code.

**Architecture:** Preserve provider-based v0.2 APIs. Add endpoint configuration, typed payment request/result, hosted-link launch, status verification and resume-aware button callbacks. An optional merchant-owned Cloudflare Worker uses authenticated users, a fixed catalog and durable D1 order storage. Browser navigation never proves payment.

**Tech stack:** Flutter/Dart, HTTP/url_launcher, Cloudflare Worker/D1, GitHub Actions.

**Spec:** User-provided “Fix CI and Make Bachs Flutter SDK Extremely Easy to Integrate” (2026-11-05).

## Constraints and review focus

- Keep existing APIs where practical; never accept Bachs secret keys in mobile configuration.
- Preserve independent merchant instances; validate endpoints, URL hosts, response identifiers and timeouts.
- Distinguish navigation cancellation from trusted payment cancellation; verify again on return/resume.
- Do not replay uncertain checkout creation with a new idempotency key.
- Test malformed responses, callback/unmount behavior, duplicate requests, webhook ordering and ownership failures.
- No production-readiness claim or live payment testing. Push existing main without force.

## Tasks

- [x] Reproduce CI lint; fix braces and normalize formatting. CI checks formatting without mutation, analyzes/tests every package and compiles backend executables.
- [x] Add failing SDK tests for BachsConfig, BachsPaymentRequest, pay, verifyPayment, verifyReturn, openCheckoutUrl and secret rejection; implement backward-compatible API and typed failures.
- [x] Extend button with result callbacks, style/child customization and resume verification; test loading and callback safety.
- [x] Implement and test isolated optional serverless starter with fixed pricing, JWT authentication, durable ownership/idempotency and raw-body signed webhook verification.
- [x] Replace example with Git-installed shop; test simulated outcomes and document real sandbox/app links setup.
- [x] Rewrite README in requested twelve-section structure; document official client-auth findings, advanced backend contract and return navigation.
- [x] Run format/analyze/tests, backend compilation, dependency audits, tracked source secret scan and review diff.
- [ ] Commit/push main, test external Git dependency and inspect/fix all relevant GitHub Actions checks.
