# Security policy

This repository is an **unofficial prototype**. Do not use it to process production payments until you've completed a security review and real sandbox verification.

- Never include Bachs secret keys, signing secrets, financial data or personal customer data in public issues, commits or screenshots.
- Do not call Bachs privileged endpoints from Flutter apps. Secret keys belong on a secure backend.
- Treat mobile redirects as UX events only, not financial proof.
- Verify signed webhooks on the raw request body; reject stale/invalid signatures.
- Store webhook event IDs durably and make fulfillment idempotent, then verify amount, currency, organization and expected order linkage.
- Consider timeouts and 5xx write outcomes ambiguous; reuse the persisted Idempotency-Key, reconcile before retrying.
- The included demo backend has no authentication or durable persistence and must not be publicly deployed.

Before publishing the project, add a private security-reporting contact or enable GitHub's private vulnerability reporting for the repository. Never disclose exploit details as a public issue.
