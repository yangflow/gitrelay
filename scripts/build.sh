#!/usr/bin/env bash
#
# build.sh — Build GitRelay.app for local use (ad-hoc signed).
#
# Usage:
#     ./scripts/build.sh
#
# Output:
#     dist/gitrelay.app  — copy to /Applications and launch.
#
# Ad-hoc signing is enough for personal use on your own Mac: Gatekeeper
# prompts once on first launch and then remembers. It is NOT enough to
# share the app with another Mac — see scripts/release.sh for that.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="gitrelay.xcodeproj"
SCHEME="gitrelay"
CONFIGURATION="Release"
DERIVED="build/DerivedData"
DIST="dist"
APP_NAME="gitrelay.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found in PATH" >&2
    exit 1
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV_DIR" != *"Xcode.app"* ]]; then
    echo "error: xcode-select currently points to '$DEV_DIR'" >&2
    echo "       Switch to the full Xcode install:" >&2
    echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

echo "==> Cleaning previous artifacts..."
rm -rf build "$DIST"
mkdir -p build "$DIST"

echo "==> Building $SCHEME ($CONFIGURATION, ad-hoc signed)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER=""

APP_SRC="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
    echo "error: did not find $APP_SRC after build" >&2
    exit 1
fi

echo "==> Copying to $DIST/..."
cp -R "$APP_SRC" "$DIST/"

echo "==> Verifying signature..."
codesign --verify --verbose=2 "$DIST/$APP_NAME"

SIZE=$(du -sh "$DIST/$APP_NAME" | cut -f1)
echo ""
echo "Built $DIST/$APP_NAME ($SIZE)"
echo ""
echo "To install:"
echo "  mv $DIST/$APP_NAME /Applications/"
echo "  xattr -cr /Applications/$APP_NAME"
echo "  open /Applications/$APP_NAME"
