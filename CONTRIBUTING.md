# Contributing to ClientIpMiddleware

Thanks for your interest in ClientIpMiddleware. This guide covers how to set up,
the conventions the project follows, and how to land a change.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting started

ClientIpMiddleware is a single Swift package. You need a Swift 6.0 toolchain
(Xcode 16+ on macOS, or the official Swift container on Linux). From the repo
root:

```sh
swift build
swift test --parallel
```

The package supports macOS 13+ and Linux. It is a Vapor `AsyncMiddleware`, and
Vapor does not ship for iOS / tvOS / watchOS, so those platforms are not
supported.

## Git hooks

Install the repo hooks once after cloning:

```sh
git config core.hooksPath .githooks
```

This wires two hooks: `pre-commit` rejects em dashes and AI-attribution tells in
staged content, and `commit-msg` rejects the same in the message and requires a
`CHANGELOG.md` entry when production source changes (opt out with
`[no-changelog]` in the commit body when no entry is warranted). The same gates
run on Linux in CI (`.github/workflows/gates.yml`) as the backstop.

## Conventions

- **Swift 6 strict concurrency** is on. Types crossing concurrency boundaries are
  `Sendable`; prove it rather than silencing with `@unchecked`.
- **Make impossible states unrepresentable.** No force-unwrapping (`!`, `try!`) in
  shipping code.
- **Testable by design.** Test behaviour through the public API, not
  implementation details.
- **Cross-platform.** The middleware builds and runs on macOS and Linux. Keep new
  code free of Darwin-only APIs, or guard platform-divergent code behind a seam.
- Read the surrounding files before writing new code and match what is already
  there. Consistency with existing code outranks personal preference.

## Tests

Tests use the **Swift Testing** framework (`@Test`, `@Suite`, `#expect`), not
XCTest. One behaviour per test, descriptive names, deterministic data, no live
network. Add coverage for any behaviour you change, especially around
`trustedProxyHops` resolution and task-local isolation.

Run `swift test --parallel` and confirm the suite passes before opening a PR. The
same build and test run on macOS and Linux in CI
(`.github/workflows/macos.yml` and `.github/workflows/linux.yml`).

## Commits

Commit messages follow Conventional Commits: `<type>(<scope>): summary`, lowercase
type, imperative mood, no trailing period, first line under 72 characters. Types:
`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`.

## Branches

Branch from the current tip of `main`:

```sh
git fetch origin main && git checkout -b feat/<topic> origin/main
```

Naming: `fix/<issue>-<topic>`, `feat/<topic>`, `chore/<topic>`, `docs/<topic>`,
`refactor/<topic>`.

## Pull requests

- One focused change per PR. If the diff spans two unrelated concerns, split it.
- Add a `CHANGELOG.md` entry under `Unreleased` for any change that touches
  shipping source. Docs, tests, and config changes do not need an entry.
- Run `swift build` and `swift test --parallel` and confirm both pass before
  opening the PR.
- Do a self-review pass on your own diff and fix what a reviewer would flag.

## Issues

For bugs, file an issue first describing the symptom, the expected behaviour, and
a reproduction, then branch with the issue number in the name. For features, an
issue is recommended when the scope is non-trivial.

## License

By contributing, you agree that your contributions are licensed under the
project's [Apache License 2.0](LICENSE).
