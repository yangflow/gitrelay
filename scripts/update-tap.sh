#!/usr/bin/env bash
#
# update-tap.sh — Push an updated Casks/gitrelay.rb to yangflow/homebrew-tap.
#
# Run this after release.sh has produced the DMG and its .sha256 file,
# and after `gh release create` has uploaded the artifacts.
#
# Usage:
#   ./scripts/update-tap.sh <version>
#   Example: ./scripts/update-tap.sh 0.2.0
#
# Requires: gh CLI authenticated with write access to yangflow/homebrew-tap.
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version>" >&2
    exit 64
fi
VERSION="$1"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like 1.0.0 (no 'v' prefix)" >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA256_FILE="$REPO_ROOT/dist/GitRelay-$VERSION.dmg.sha256"

if [[ ! -f "$SHA256_FILE" ]]; then
    echo "error: $SHA256_FILE not found — run release.sh first" >&2
    exit 1
fi
SHA256="$(cat "$SHA256_FILE")"

echo "==> Updating yangflow/homebrew-tap to GitRelay $VERSION ($SHA256)..."

CASK=$(cat <<CASK
cask "gitrelay" do
  version "$VERSION"
  sha256 "$SHA256"

  url      "https://github.com/yangflow/gitrelay/releases/download/v#{version}/GitRelay-#{version}.dmg"
  name     "GitRelay"
  desc     "Local-first Git repository mirroring workspace for macOS"
  homepage "https://github.com/yangflow/gitrelay"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "GitRelay.app"

  binary "#{appdir}/GitRelay.app/Contents/MacOS/gitrelayctl", target: "gitrelayctl"

  zap trash: [
    "~/.local/share/gitrelay",
    "~/Library/Caches/com.yangflow.gitrelay",
    "~/Library/Preferences/com.yangflow.gitrelay.plist",
  ]
end
CASK
)

CONTENT=$(printf '%s' "$CASK" | base64 | tr -d '\n')

# Fetch the current file SHA (required by GitHub API for updates).
FILE_SHA=$(gh api repos/yangflow/homebrew-tap/contents/Casks/gitrelay.rb \
    --jq '.sha' 2>/dev/null || true)

if [[ -n "$FILE_SHA" ]]; then
    gh api repos/yangflow/homebrew-tap/contents/Casks/gitrelay.rb \
        --method PUT \
        -f message="chore: update gitrelay to $VERSION" \
        -f content="$CONTENT" \
        -f sha="$FILE_SHA" \
        --jq '.content.html_url'
else
    gh api repos/yangflow/homebrew-tap/contents/Casks/gitrelay.rb \
        --method PUT \
        -f message="feat: add gitrelay $VERSION cask" \
        -f content="$CONTENT" \
        --jq '.content.html_url'
fi

echo ""
echo "Tap updated. Users can install with:"
echo "  brew tap yangflow/tap"
echo "  brew install --cask gitrelay"
