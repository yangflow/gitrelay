# GitRelay

Git continuity for the repositories that matter.

GitRelay is a native macOS workspace for keeping one source repository mirrored to one or more destinations. Each Mirror combines its source, destinations, policy, health, and run history into one product object. Git work runs locally through `git clone --mirror`, `git fetch --prune`, and `git push --mirror`.

[中文](./README.zh-CN.md)

## How GitRelay works

- Smart views surface Mirrors that need attention, are running, are paused, or share a label.
- The Mirror list stays visible for search, comparison, and fast switching.
- The detail pane is state-driven. It explains the current condition and presents the next useful action before showing history and diagnostics.
- Add Mirror supports connected-service browsing and direct Git URLs in one flow.
- Connections and global defaults live in the native Settings window.
- One source can fan out to multiple Git remotes and filesystem archives.

GitRelay supports GitHub, GitLab, Gitea, Gitee, Bitbucket, and self-hosted Git servers through SSH Agent, explicit SSH keys, or HTTPS tokens stored in macOS Keychain.

## Highlights

- Full branch and tag mirroring with prune support
- Multi-destination partial-failure reporting
- Strict destructive-push protection with dry-run confirmation
- Independent sync and verification schedules
- Per-destination freshness and integrity state
- Search, labels, health filters, sorting, and a 200-Mirror workspace target
- Menu bar, Widget, Shortcuts, App Intents, notifications, and CLI using the same Mirror UUIDs
- Webhook-triggered local sync
- Git LFS and release asset mirroring
- Filesystem archives as tar.gz, zip, or Git bundle
- Config export and import without token values
- Credential redaction in logs and persisted failures
- English and Simplified Chinese localization

## Local execution boundary

GitRelay is local-first, not a hosted service. Scheduled runs and webhook handling require the Mac to be awake and the GitRelay process to be available. After sleep or interruption, GitRelay reports freshness and missed work instead of claiming continuous cloud availability. Manual sync, existing Mirrors, local archives, and the CLI do not depend on provider browsing APIs.

## Requirements

- macOS 26.2 or later
- Apple Silicon or Intel
- Git at `/usr/bin/git`, `/usr/local/bin/git`, or `/opt/homebrew/bin/git`

## Install

### Homebrew

```bash
brew tap yangflow/tap
brew install --cask gitrelay
```

### Download

Download the latest DMG from [Releases](https://github.com/yangflow/gitrelay/releases), then drag GitRelay to Applications.

The current community build is ad-hoc signed. On first launch, right-click the app and choose Open, or run:

```bash
xattr -cr /Applications/GitRelay.app
```

### Build from source

```bash
git clone https://github.com/yangflow/gitrelay.git
cd gitrelay
open gitrelay.xcodeproj
```

Select the `gitrelay` scheme and press `Command-R`.

## Add your first Mirror

1. Click the add button in the Mirror list.
2. Browse a connected service or choose Enter Git URL.
3. Confirm the source and add one or more destinations.
4. Choose credentials and policy. New Mirrors inherit the defaults from Settings.
5. Add the Mirror and start its first sync.

The same editor is used later for changes, so source, destinations, credentials, and policy remain in one place.

## CLI

The app bundle includes `GitRelay.app/Contents/MacOS/gitrelayctl`.

```bash
gitrelayctl list
gitrelayctl sync <mirror-uuid-or-unique-name>
gitrelayctl status [<mirror-uuid-or-unique-name>]
gitrelayctl logs <mirror-uuid-or-unique-name> [--tail N]
```

CLI status JSON uses `mirrors`, `mirrorID`, and `mirrorName`. A display name must be unique; UUID lookup is stable.

## Data and privacy

| Data | Location |
|---|---|
| Mirror plans | `~/.local/share/gitrelay/mirrors.json` |
| Compact health state | `~/.local/share/gitrelay/mirror-state.json` |
| Authoritative run records | `~/.local/share/gitrelay/logs/` |
| Bare Mirror cache | `~/.local/share/gitrelay/mirrors/<uuid>/` |
| Verification scratch data | `~/.local/share/gitrelay/verify-scratch/` |
| HTTPS tokens and managed secrets | macOS Keychain |
| Widget health snapshot | App Group `group.com.yangflow.gitrelay` |
| CLI binary | `GitRelay.app/Contents/MacOS/gitrelayctl` |

Mirror plans contain repository URLs and policy, but no token values or private key material. HTTPS tokens and managed secrets stay in macOS Keychain. Exported configuration files omit secrets, and GitRelay redacts credentials before persisting errors or logs.

## Development checks

```bash
python3 scripts/check_string_catalog.py
python3 scripts/check_unlocalized_strings.py
xcodebuild test -project gitrelay.xcodeproj -scheme gitrelay \
  -destination 'platform=macOS' -testLanguage en -testRegion US \
  CODE_SIGNING_ALLOWED=NO
```

## License

MIT. See [LICENSE](./LICENSE).
