# GitRelay

Mirror any Git repository to any other Git repository, automatically — from your Mac.

GitRelay is a native macOS app that manages one-way mirror syncs between Git hosting platforms. Point it at a source and one or more destinations, choose a schedule, and it handles the rest: `git clone --mirror`, `git fetch --prune`, `git push --mirror`, all running quietly in the background while you work.

It supports any combination of GitLab, GitHub, Gitea, Gitee, Bitbucket, or self-hosted Git servers — SSH Agent, SSH key, and HTTPS token auth included. The UI follows the system language (English and Simplified Chinese).

[中文](./README.zh-CN.md)

---

## Features

- **Multi-repo sidebar** — manage any number of repo pairs from one window; search and filter by name, URL, tag, or sync status
- **1→N fan-out** — one source, multiple destinations (Git remotes and/or filesystem archives)
- **Full mirror sync** — all branches and tags, one direction, src → dst
- **Tags / groups** — label repos and run bulk actions by tag
- **Destructive push protection** — dry-runs mirror pushes and prompts before target ref deletes or forced updates by default
- **Sync health dashboard** — sidebar and menu bar summaries for today's success, failure, and not-run counts; detail sparkline for recent history
- **Scheduled sync** — per-repo frequency: manual, 15 min, 30 min, 1 h, 1 day
- **Quiet hours** — skip scheduled syncs inside a local-time window (manual sync still works)
- **Auth flexibility** — SSH Agent, SSH key path, or HTTPS token (stored in macOS Keychain)
- **Token scope check** — validates provider token scopes on connect and warns when permissions are missing
- **In-app SSH key generation** — create an ed25519 key and copy the public key to the clipboard
- **Multi-account** — personal / work (and custom) labels per provider for Browse Remote
- **Menu bar quick access** — aggregate status, search, and per-repo sync without opening the main window
- **Shortcuts / App Intents** — Sync and Sync All from Shortcuts.app
- **gitrelayctl CLI** — headless companion sharing the GUI config (`list` / `sync` / `status` / `logs`); binary at `GitRelay.app/Contents/MacOS/gitrelayctl`
- **Webhook instant sync** — trigger a run on push instead of waiting for the next schedule tick
- **Release asset mirroring** — mirror GitHub/GitLab Releases and their binary assets
- **Filesystem archives** — push a snapshot to disk as tar.gz or git bundle
- **Shallow clone / ref filter** — depth and ref-glob options for large repos
- **Org auto-subscribe** — watch an org/user and prompt when new repos appear
- **Git LFS objects** — mirrored automatically when `git-lfs` is installed
- **Transient git retry** — exponential backoff on flaky network errors within a sync run
- **Config export / import** — move repo setup between Macs without copying secrets
- **Desktop / lock-screen widgets** — sync-health glance via App Group `group.com.yangflow.gitrelay`
- **Touch ID gate** — biometric confirmation before revealing tokens or high-risk actions
- **LRU bare-clone cleanup** — cache quota so local mirrors do not grow without bound
- **en-US + zh-Hans** — UI follows the system language
- **Sync log** — per-run log with credential redaction and error classification
- **Commit delta** — shows how many commits src is ahead of dst before each push

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel
- `git` installed (`/usr/bin/git`, `/usr/local/bin/git`, or `/opt/homebrew/bin/git`)

---

## Install

### Homebrew

```bash
brew tap yangflow/tap
brew install --cask gitrelay
```

### Download DMG

Go to [Releases](https://github.com/yangflow/gitrelay/releases) and download the latest `GitRelay-x.y.z.dmg`. Open it and drag GitRelay to Applications.

> Unsigned build: right-click → Open on first launch, or run `xattr -cr /Applications/GitRelay.app`

### Build from source

```bash
git clone https://github.com/yangflow/gitrelay.git
cd gitrelay
open gitrelay.xcodeproj
```

Select the `gitrelay` scheme, press ⌘R.

---

## Usage

1. Click **+** in the toolbar or the empty-state button to add a repo pair.
2. Enter a name, the source URL, and one or more destination URLs (or archive paths).
3. Choose the auth method for each side — SSH Agent requires no extra setup if `ssh-agent` is already running.
4. Set a sync frequency and click **Add**.
5. GitRelay clones the source as a bare mirror on first sync, then fetches and pushes on every subsequent run.

The menu bar icon shows aggregate status: a warning triangle if any repo has a sync failure. For scripting, run `GitRelay.app/Contents/MacOS/gitrelayctl --help`.

---

## Data locations

| What | Where |
|------|-------|
| Repo configs | `~/.local/share/gitrelay/repos.json` (shared by the app and `gitrelayctl`) |
| Mirror clones | `~/.local/share/gitrelay/mirrors/<uuid>/` |
| HTTPS tokens | macOS Keychain |
| Widget health snapshot | App Group `group.com.yangflow.gitrelay` (`widget-health-snapshot.json`) |
| gitrelayctl binary | `GitRelay.app/Contents/MacOS/gitrelayctl` |

---

## Regenerate app icon

The AppIcon PNGs are exported from the committed source artwork and checked in.
Edit `scripts/assets/gitrelay-status-first-01.png`, then regenerate:

```bash
# macOS
swift scripts/generate-icon.swift

# Linux / CI-friendly
python3 scripts/generate-icon.py
```

The AppIcon is a 3D merge-arrow mark on a charcoal squircle. The menu-bar status
item is separate: a monochrome Y-branch template drawn from
`GitRelayCore/Design/GitRelayMark.swift` via `MenuBarBranchMark` — no color
plate, red-tint on failure. `GitRelayMarkTests` pins that geometry.

---

## License

MIT — see [LICENSE](./LICENSE).
