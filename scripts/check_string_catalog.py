#!/usr/bin/env python3
"""Validate Localizable.xcstrings has en + zh-Hans for every entry."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOGS = (
    ROOT / "gitrelay" / "Localizable.xcstrings",
    ROOT / "gitrelayWidget" / "Localizable.xcstrings",
    ROOT / "gitrelay" / "InfoPlist.xcstrings",
)
REQUIRED_LOCALES = ("en", "zh-Hans")

# Recent UI keys from #55–#73 that must stay bilingual (issue #65).
REQUIRED_KEYS = {
    ROOT / "gitrelay" / "Localizable.xcstrings": (
        "Queued",
        "Sync Concurrency",
        "Max concurrent syncs: %lld",
        "Manual, webhook, and scheduled syncs share this limit. Extra requests wait until a slot is available. Waiting work is discarded when GitRelay quits.",
        "Open at Login",
        "Keep in Menu Bar when closing main window",
        "Startup & Menu Bar",
        "Open at Login needs approval in System Settings → General → Login Items.",
        "Could not enable Open at Login. Check System Settings → Login Items.",
        "Security",
        "Notifications",
        "Schedule",
        "Webhook",
        "Cache",
        "Configuration",
        "More Options",
        "Add and Start Syncing",
        "Source URL",
        "Target URL",
        "Additional Targets",
        "Targets",
        "Source Authentication",
        "Authentication Method",
        "Archive Directory",
        "Re-enter credentials",
        "Open Log",
        "Source repository not found",
        "Destination repository not found",
        "Personal Access Token",
        "Token",
        "Language",
        "Follow System",
        "English",
        "Simplified Chinese",
        "Provider",
        "Gitea Host",
        "Gitea API Token",
        # Connected-service source selection inside Add Mirror.
        "Host",
        "Connection",
        "Account",
        "Add Account",
        "Remove Account",
        "Gitea Account",
        "Choose a Connected Service",
        "Choose Source Repositories",
        "Choose Destinations and Policy",
        "Start Over",
        "%lld selected",
        "Private repository",
        "Reused %lld",
        "Failed %lld",
        # Quiet menu-bar popover status line (issues #87 / #107).
        "Schedule paused · %@",
        "Missed runs: %lld · catching up",
        "Manual pause",
        "Quiet hours",
        "Low Power Mode",
        "Metered network",
        "Low Power Mode · Metered network",
        # Add-sheet preflight captions and buttons (issue #101).
        "This mirror already exists. Open it or change the target.",
        "The destination repository does not exist. An empty one will be created on %@.",
        "The source refused the credentials. Take a look at its token or account.",
        "The destination refused the credentials. Take a look at its token or account.",
        "Create and Start Sync",
        "Open the Existing One",
        "Add Anyway",
        # Different-history sheet copy and its three choices (issue #102).
        "Target already has different history",
        "%@ already has %lld commits that the source does not.",
        "%@ already has commits that the source does not.",
        "Continuing replaces those commits with the source, and the branches already on the target are replaced.",
        "You can push to check branches under %@ first and leave the target's own branches where they are.",
        "Overwrite and Sync",
        "Push to Check Branch",
        # Security-tab account list: last used, 测试, 添加令牌 (issue #104).
        "Accounts",
        "Add Token",
        "Account Name",
        "Test",
        "Never used",
        "Just now",
        "Token works",
        "Token works; scopes not reported",
        "Missing scope: %@",
        "Token rejected",
        "Permission denied",
        "Account not found",
        "Could not reach the host",
        "Response could not be read",
        "The host refused the check",
        "Test failed",
        "No token saved",
        "Token saved in Keychain",
        "Show accounts from every provider",
        "Ask %@ whether the saved token still works",
        "Require Touch ID or password for sensitive actions",
        # Cache per-repo size + evict (issue #105).
        "Local Mirrors",
        "Clean",
        "Clean All",
        "No local mirrors.",
        # Webhook tab: hook path, last event, send test (issue #106).
        "Repository Hook URL",
        "Last Event",
        "Send Test",
        "Enable instant webhook sync on a repository to get a hook path.",
        "Unknown repository",
        "%@ · %@ · %lld",
    ),
    # Quiet widget face (issue #89): 今日 + three counts, no glyph-leading keys.
    ROOT / "gitrelayWidget" / "Localizable.xcstrings": (
        "All mirrors look healthy",
        "Not Synced",
        "Queued",
        "Stale",
        "Sync Health",
        "Syncing",
        "Today",
        "Today's mirror sync status at a glance.",
        "Today: %lld succeeded, %lld failed, %lld not run",
    ),
    ROOT / "gitrelay" / "InfoPlist.xcstrings": (
        "NSFaceIDUsageDescription",
        "NSFocusStatusUsageDescription",
    ),
}

# Widget catalog must stay widget-only; GitRelayCore in the extension must not
# auto-extract the app catalog (SWIFT_EMIT_LOC_STRINGS=NO on gitrelayWidget).
WIDGET_CATALOG = ROOT / "gitrelayWidget" / "Localizable.xcstrings"
WIDGET_MAX_KEYS = 9

# The widget target builds with STRING_CATALOG_GENERATE_SYMBOLS=YES, so every
# widget catalog key has to derive a Swift identifier. Keys such as "✓ %lld"
# do not, and break the Xcode 26 build.
SYMBOL_GENERATING_CATALOGS = (ROOT / "gitrelayWidget" / "Localizable.xcstrings",)


def validate_catalog(catalog: Path) -> list[str]:
    if not catalog.is_file():
        return [f"Missing string catalog: {catalog.relative_to(ROOT)}"]

    data = json.loads(catalog.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "en":
        return [f"{catalog.relative_to(ROOT)}: sourceLanguage must be 'en', got {data.get('sourceLanguage')!r}"]

    strings = data.get("strings")
    if not isinstance(strings, dict) or not strings:
        return [f"{catalog.relative_to(ROOT)}: catalog has no strings"]

    errors: list[str] = []
    for key, entry in strings.items():
        locs = entry.get("localizations") if isinstance(entry, dict) else None
        if not isinstance(locs, dict):
            errors.append(f"{catalog.relative_to(ROOT)} {key!r}: missing localizations")
            continue
        for locale in REQUIRED_LOCALES:
            unit = locs.get(locale, {}).get("stringUnit", {})
            value = unit.get("value")
            if not isinstance(value, str) or value == "":
                errors.append(f"{catalog.relative_to(ROOT)} {key!r}: missing {locale} value")

    for key in REQUIRED_KEYS.get(catalog, ()):
        entry = strings.get(key)
        if not isinstance(entry, dict):
            errors.append(f"{catalog.relative_to(ROOT)}: missing required key {key!r}")
            continue
        locs = entry.get("localizations")
        if not isinstance(locs, dict):
            errors.append(f"{catalog.relative_to(ROOT)} {key!r}: missing localizations")
            continue
        for locale in REQUIRED_LOCALES:
            unit = locs.get(locale, {}).get("stringUnit", {})
            value = unit.get("value")
            if not isinstance(value, str) or value == "":
                errors.append(
                    f"{catalog.relative_to(ROOT)} required key {key!r}: missing {locale} value"
                )

    if catalog in SYMBOL_GENERATING_CATALOGS:
        for key in strings:
            if not key[:1].isascii() or not key[:1].isalpha():
                errors.append(
                    f"{catalog.relative_to(ROOT)} {key!r}: key must start with an ASCII "
                    "letter so STRING_CATALOG_GENERATE_SYMBOLS can derive a Swift symbol"
                )

    if catalog == WIDGET_CATALOG and len(strings) > WIDGET_MAX_KEYS:
        errors.append(
            f"{catalog.relative_to(ROOT)}: expected at most {WIDGET_MAX_KEYS} keys "
            f"(widget-only strings), found {len(strings)}"
        )

    return errors


def main() -> int:
    all_errors: list[str] = []
    total_keys = 0
    for catalog in CATALOGS:
        errors = validate_catalog(catalog)
        all_errors.extend(errors)
        if not errors and catalog.is_file():
            data = json.loads(catalog.read_text(encoding="utf-8"))
            total_keys += len(data.get("strings", {}))

    if all_errors:
        print(f"Found {len(all_errors)} catalog issue(s):")
        for err in all_errors[:50]:
            print(f"  {err}")
        if len(all_errors) > 50:
            print(f"  ... and {len(all_errors) - 50} more")
        return 1

    print(
        f"Catalog OK: {total_keys} keys across {len(CATALOGS)} catalogs, "
        f"sourceLanguage=en, locales={', '.join(REQUIRED_LOCALES)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
