#!/usr/bin/env python3
"""Validate Localizable.xcstrings has en + zh-Hans for every entry."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "gitrelay" / "Localizable.xcstrings"
REQUIRED_LOCALES = ("en", "zh-Hans")


def main() -> int:
    if not CATALOG.is_file():
        print(f"Missing string catalog: {CATALOG.relative_to(ROOT)}")
        return 1

    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "en":
        print(f"sourceLanguage must be 'en', got {data.get('sourceLanguage')!r}")
        return 1

    strings = data.get("strings")
    if not isinstance(strings, dict) or not strings:
        print("Catalog has no strings")
        return 1

    errors: list[str] = []
    for key, entry in strings.items():
        locs = entry.get("localizations") if isinstance(entry, dict) else None
        if not isinstance(locs, dict):
            errors.append(f"{key!r}: missing localizations")
            continue
        for locale in REQUIRED_LOCALES:
            unit = locs.get(locale, {}).get("stringUnit", {})
            value = unit.get("value")
            if not isinstance(value, str) or value == "":
                errors.append(f"{key!r}: missing {locale} value")

    if errors:
        print(f"Found {len(errors)} catalog issue(s):")
        for err in errors[:50]:
            print(f"  {err}")
        if len(errors) > 50:
            print(f"  ... and {len(errors) - 50} more")
        return 1

    print(
        f"Catalog OK: {len(strings)} keys, "
        f"sourceLanguage=en, locales={', '.join(REQUIRED_LOCALES)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
