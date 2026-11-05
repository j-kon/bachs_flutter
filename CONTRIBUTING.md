# Contributing

Thanks for helping grow the Bachs Flutter ecosystem.

1. Open an issue describing an improvement. Avoid posting real API keys or customer data.
2. Keep the Flutter package public-client-only; never add privileged endpoints or secret credentials to it.
3. For server APIs, link the relevant official Bachs endpoint documentation and include MockClient-based tests.
4. Every webhook change needs signature tests for stale timestamps, tampered bodies and rotated V2 signatures.
5. Run the formatting, analysis, test, build and security commands in [docs/VALIDATION.md](docs/VALIDATION.md) for every affected package before requesting a review.
6. Add new features to `CHANGELOG.md` and update README usage.

By participating you agree to follow respectful, constructive project communication.
