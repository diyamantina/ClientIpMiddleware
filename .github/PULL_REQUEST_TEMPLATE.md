<!-- One focused change per PR. If the diff spans two unrelated concerns, split it. See CONTRIBUTING.md. -->

## What

<!-- What does this change do? -->

## Why

<!-- Why is it needed? Link the issue it closes, e.g. Closes #123. -->

## How to verify

<!-- Commands or steps a reviewer can run. -->

```sh
swift build
swift test --parallel
```

## Checklist

- [ ] `swift build` and `swift test --parallel` pass.
- [ ] Builds on both macOS and Linux (or the change is platform-neutral).
- [ ] Code follows the conventions in [CONTRIBUTING.md](../CONTRIBUTING.md).
- [ ] `CHANGELOG.md` updated under `Unreleased` (or this change is docs / tests / config only).
- [ ] No AI attribution and no em dashes in commits, comments, or this description.
