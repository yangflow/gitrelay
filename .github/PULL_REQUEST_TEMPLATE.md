## Summary

<!-- What does this PR change and why. Keep it short — one paragraph. -->

## Kind of change

- [ ] Bug fix (regression test added)
- [ ] New feature
- [ ] Refactor (no behavior change)
- [ ] Docs / scaffolding only

## Test plan

- [ ] `xcodebuild test -project gitrelay.xcodeproj -scheme gitrelay -destination 'platform=macOS' -only-testing:gitrelayTests CODE_SIGNING_ALLOWED=NO` exits 0
- [ ] Added / updated unit tests for the code path this PR touches
- [ ] Manually verified in the app (what you clicked and what you saw)

## Credential safety

<!-- If this PR touches SyncEngine, GitRunner, or KeychainService: confirm
that no token or key material can appear in log lines or error messages. -->

## Swift concurrency

<!-- If this PR adds a new class or struct that holds mutable state, say
whether it's @MainActor / Sendable / actor, and why. -->

## Screenshots

<!-- Optional for UI changes. -->
