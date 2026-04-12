#!/usr/bin/env bash
#
# release.sh — Build a GitRelay release artifact (.dmg).
#
# Modes are detected from env vars:
#
#   unsigned     (default)
#     Produces dist/GitRelay-<version>.dmg ad-hoc signed.
#     Gatekeeper will warn on first launch on another Mac.
#
#   signed       DEVELOPER_ID_APPLICATION=<cert-name>
#     Produces a DMG signed by the named "Developer ID Application"
#     certificate. Trusted signature but Gatekeeper still warns until
#     notarization.
#
#   notarized    signed +
#                APPLE_ID=<apple-id-email>
#                APPLE_TEAM_ID=<10-char-team-id>
#                APPLE_APP_PASSWORD=<app-specific-password>
#     Uploads to Apple's notary service, waits, staples, and produces
#     a fully Gatekeeper-approved DMG.
#
# Usage:
#     ./scripts/release.sh <version>
#     VERSION must be a plain semver like 1.0.0 (no leading 'v').
#
# Output in dist/:
#     gitrelay.app                     — built app bundle
#     GitRelay-<version>.dmg           — distributable disk image
#     GitRelay-<version>.dmg.sha256    — SHA256 checksum
#
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <version>" >&2
    echo "example: $0 1.0.0" >&2
    exit 64
fi
VERSION="$1"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like 1.0.0 (no 'v' prefix)" >&2
    exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found; install Xcode and run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

PROJECT="gitrelay.xcodeproj"
SCHEME="gitrelay"
CONFIGURATION="Release"
DERIVED="build/DerivedData"
DIST="dist"
APP_NAME="gitrelay.app"
DMG_NAME="GitRelay-$VERSION.dmg"

# -----------------------------------------------------------------------------
# Mode detection
# -----------------------------------------------------------------------------

MODE="unsigned"
SIGN_IDENTITY="-"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    MODE="signed"
    SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
fi
if [[ "$MODE" == "signed" \
   && -n "${APPLE_ID:-}" \
   && -n "${APPLE_TEAM_ID:-}" \
   && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    MODE="notarized"
fi

echo "==> GitRelay $VERSION — mode: $MODE"

# -----------------------------------------------------------------------------
# Clean + build
# -----------------------------------------------------------------------------

rm -rf build "$DIST"
mkdir -p build "$DIST"

echo "==> Building ($CONFIGURATION, identity=$SIGN_IDENTITY)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES

APP_SRC="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
    echo "error: built app missing at $APP_SRC" >&2
    exit 1
fi
cp -R "$APP_SRC" "$DIST/"

codesign --verify --verbose=2 "$DIST/$APP_NAME"

# -----------------------------------------------------------------------------
# Notarize (optional)
# -----------------------------------------------------------------------------

if [[ "$MODE" == "notarized" ]]; then
    echo "==> Zipping for notarization..."
    NOTARIZE_ZIP="$DIST/GitRelay-notarize.zip"
    ditto -c -k --keepParent "$DIST/$APP_NAME" "$NOTARIZE_ZIP"

    echo "==> Submitting to Apple notary service..."
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait

    echo "==> Stapling..."
    xcrun stapler staple "$DIST/$APP_NAME"
    rm -f "$NOTARIZE_ZIP"
fi

# -----------------------------------------------------------------------------
# DMG
# -----------------------------------------------------------------------------

echo "==> Building DMG..."
DMG_PATH="$DIST/$DMG_NAME"
STAGING="$(mktemp -d)"
cp -R "$DIST/$APP_NAME" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
    -volname "GitRelay $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$STAGING"

shasum -a 256 "$DMG_PATH" | awk '{print $1}' > "$DMG_PATH.sha256"
echo "==> SHA256: $(cat "$DMG_PATH.sha256")"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "Release $VERSION built in $DIST/:"
ls -la "$DIST"
echo ""
echo "Next steps:"
echo "  gh release create v$VERSION \\"
echo "    --title 'GitRelay $VERSION' \\"
echo "    --notes-file CHANGELOG.md \\"
echo "    '$DMG_PATH#GitRelay $VERSION (DMG)' \\"
echo "    '$DMG_PATH.sha256#SHA256'"
if [[ "$MODE" == "unsigned" ]]; then
    echo ""
    echo "Note: unsigned build. Recipients must right-click → Open on first launch,"
    echo "      or run: xattr -cr /Applications/$APP_NAME"
fi
