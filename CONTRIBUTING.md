# Contributing to GitRelay

Thanks for your interest in GitRelay. This document covers how to build, test, and send changes.

## Ground rules

- Be kind. Bug reports and PRs are welcome from everyone.
- Discuss large changes in an issue before starting so we can align on scope and design.
- GitRelay intentionally does not modify the user's dotfiles or global Git configuration. No change should break that guarantee.

## Prerequisites

- macOS 26.2 or later
- Xcode 26.2 or later
- Apple Silicon or Intel

## Build

```bash
git clone https://github.com/yangflow/gitrelay.git
cd gitrelay
open gitrelay.xcodeproj
```

Select the `gitrelay` scheme, press ⌘R.

## Test

```bash
xcodebuild test \
  -project gitrelay.xcodeproj \
  -scheme gitrelay \
  -destination 'platform=macOS' \
  -only-testing:gitrelayTests \
  CODE_SIGNING_ALLOWED=NO
```

Before opening a PR, make sure this command exits 0.

If you add a bug fix, add a regression test that fails on the old code. New services need tests covering at least the happy path and one error case.

## Code style

- Use Swift concurrency deliberately: `@MainActor`, actors, and `Sendable` should match ownership boundaries.
- SwiftUI for all views. No AppKit unless unavoidable at the menu bar or window layer.
- Prefer plain structs and enums with associated values over class hierarchies.
- No force unwraps on user input. Throw typed errors.
- No unrelated refactors in bug-fix PRs.

## Commit messages

Short imperative subject (under ~70 chars), optional body explaining the *why*:

```
<type>: <short subject, imperative>

<optional body explaining the why, not the what>
```

Type prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.

## Pull request flow

1. Fork + branch off `main`.
2. Implement the change. Add or update tests.
3. Run the test command above. Confirm it exits 0.
4. Push, open a PR against `main`.
5. In the PR body: describe the *why*, not the *what*.

## Areas that need extra care

- **`SyncEngine`:** errors must never leak credentials into logs. `redactCredentials` is the gate; if you add a new log line that might contain a URL, pass it through.
- **`GitRunner`:** all Git subprocess calls. If you add a new command, make sure it handles the cancelled signal path (`GitError.cancelled`) and cleans up any partially written state.
- **`KeychainService`:** tokens must stay in the Keychain. Never store a token or private-key material in `MirrorPlan`, exported configuration, or logs.
- **`SyncScheduler`:** `Timer` fires on the main run loop. All callbacks must be `MainActor`-safe. Use `MainActor.assumeIsolated` in the timer closure if needed.
- **Concurrency:** `MirrorOperationsController` owns queued and in-progress work. `MirrorOperationLease` prevents sync and verification from mutating the same Mirror concurrently, while `SyncConcurrencyGate` caps global sync throughput. Do not bypass these boundaries.

## Security

If you discover a security issue, please email the maintainer instead of opening a public issue.

## License

By contributing to GitRelay you agree your contributions are licensed under the [MIT License](./LICENSE).
