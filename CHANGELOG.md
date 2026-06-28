# Changelog

All notable changes to ClientIpMiddleware are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `.swiftformat` and `.swiftlint.yml` at the repository root as the committed
  source of truth for formatting and linting.
- `scripts/check-namespacing.sh` (one top-level type per file) and a `pre-push`
  git hook that runs the namespacing gate, `swiftformat --lint`,
  `swiftlint --strict`, build, and test before a push reaches the remote.
- A `Style` CI workflow that runs `swiftformat --lint` and `swiftlint --strict`
  as required checks, backstopping the local hooks.

### Changed
- Reformatted the sources with the committed SwiftFormat configuration. No
  behavior change; the compiled surface is identical.
- Updated the local `commit-msg` and `pre-commit` hooks to the shared canon
  implementation while keeping the CHANGELOG-entry gate.

## [1.0.1] - 2026-06-02

Packaging and repository hardening. No library code changed; the compiled
surface is identical to 1.0.0.

### Added
- `LICENSE` file (Apache 2.0). The 1.0.0 tag declared Apache 2.0 in the README
  but shipped no license file; consumers pinning `from: "1.0.0"` resolved a tree
  without one.
- Community health docs: `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`,
  `CONTRIBUTING.md`, and this `CHANGELOG.md`.
- GitHub issue forms (bug + feature), a PR template, and a priority labeler
  workflow.
- Per-platform `Linux` and `macOS` CI workflows with status badges, a `Gates`
  workflow, and local git hooks enforcing no em dashes, no AI attribution, and a
  CHANGELOG entry when production source changes.

## [1.0.0] - 2026-05-10

Initial public release.

### Added
- `ClientIpMiddleware`, a Vapor `AsyncMiddleware` that captures the client IP and
  `User-Agent` of each inbound request into `ClientContext` task-locals, so
  OpenAPI-generated handlers (which never see Vapor's `Request`) can read them.
- `trustedProxyHops` configuration for client-IP selection:
  - `0` (default, secure): ignore `X-Forwarded-For` entirely and use the
    connection's `remoteAddress`.
  - `n >= 1`: peel `n` hops off the right of `X-Forwarded-For`, falling back to
    `remoteAddress` when the header is absent or shorter than `n` entries.
- 33 tests across 3 suites: task-local semantics, Vapor integration across the
  trusted-proxy-hops range, and an adversarial / malformed-input suite (XFF edge
  cases, IPv6, whitespace, cross-request isolation, and a 100-fold concurrent
  burst).
- CI on macOS and on Linux (Swift 6.0 container).

[Unreleased]: https://github.com/mihaelamj/ClientIpMiddleware/compare/1.0.1...HEAD
[1.0.1]: https://github.com/mihaelamj/ClientIpMiddleware/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/mihaelamj/ClientIpMiddleware/releases/tag/1.0.0
