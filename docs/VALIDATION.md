# Validation and security checks

CI pins **Flutter 3.47.5**, including **Dart 3.13.4**, for the Flutter package,
example, and server. Use this version locally so formatter output matches CI.
Formatting checks do not rewrite files or hide formatting failures.

Run from the repository root:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Run in `server/`:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test bin
dart analyze --fatal-infos
dart test
mkdir -p build
dart compile exe bin/server.dart -o build/bachs-server
dart compile exe bin/example_merchant_backend.dart -o build/example-merchant-backend
```

The example manifest demonstrates Git installation. Before testing unpublished
local changes, create `example/pubspec_overrides.yaml`:

```yaml
dependency_overrides:
  bachs_flutter:
    path: ..
```

Run in `example/`:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Remove the override afterward. The regular CI example job creates this override
so it tests the checked-out change. The optional `workflow_dispatch` input
`git_smoke: true` adds a separate job without an override, proving the committed
Git dependency resolves and passes example analysis/tests. Run it after the
referenced SDK change has been pushed. It does not validate unpublished changes.

Run in `serverless/` using Node 24:

```sh
npm ci
npm test
npm run check
npm run build
npm audit --audit-level=low
```

The Worker build is a local dry run; it does not deploy infrastructure or charge
an account. See [the serverless guide](SERVERLESS.md) for deployment and integration coverage.

## Security gates

Run from the repository root:

```sh
python3 -m unittest discover -s tool -p 'test_*.py'
python3 tool/security_check.py secrets
python3 tool/security_check.py osv
```

- The OSV check queries `https://api.osv.dev/v1/querybatch` for every distinct
  hosted package name/version in the root, server, and example `pubspec.lock`
  files, including transitive and development dependencies. Any advisory fails
  the check. Network failures, unsupported registries, unexpected lock layouts,
  or incomplete/paginated responses fail clearly rather than reporting a clean
  audit. Only package names and versions are sent. SDK, Git, and path sources
  are not covered by OSV; project code is checked by tests and analysis.
- The secret check reads the current contents of Git-tracked files, reporting
  only path, line, and credential type. It detects Bachs API/webhook secrets,
  GitHub tokens, AWS access keys, and private-key headers. Exact inert fixture
  values are allowed only in test directories and `.example` files; those files
  are still scanned for other credentials. This is a targeted pattern scanner,
  not a complete secret detector, and does not scan Git history, ignored files,
  or newly created files until they are tracked. If a secret was committed,
  rotate it and review history even after the current-file scan passes.
- `npm audit` covers the Worker's locked production and development dependency
  graph and fails on low or greater severity.
- Dependabot requests weekly updates for Pub (root/server/example), npm
  (`serverless/`), and GitHub Actions. GitHub supports
  [Pub dependency updates](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories)
  and [Dart dependency review](https://github.blog/security/supply-chain-security/githubs-supply-chain-security-features-now-support-dart/).
- PRs run GitHub's dependency review action at the low-severity threshold.
  The repository dependency graph must be enabled. Private repositories need
  the applicable GitHub security entitlement; see
  [dependency review configuration](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/configuring-the-dependency-review-action).
  This workflow cannot enable repository security settings or prove they are
  enabled. Repository alerts, secret scanning, and push protection must be
  checked separately by a repository administrator.

An audit with zero known advisories is evidence about the queried database at
that time, not a guarantee that dependencies or application code are secure.
Local unit tests do not establish a live payment, webhook delivery, merchant
fulfillment, or platform-native browser behavior; those need sandbox integration
checks before production release.
