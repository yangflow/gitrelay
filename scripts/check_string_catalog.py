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
)
REQUIRED_LOCALES = ("en", "zh-Hans")


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
