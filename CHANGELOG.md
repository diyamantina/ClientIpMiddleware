# Changelog

All notable changes to ClientIpMiddleware are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/mihaelamj/ClientIpMiddleware/compare/1.0.0...HEAD
[1.0.0]: https://github.com/mihaelamj/ClientIpMiddleware/releases/tag/1.0.0
