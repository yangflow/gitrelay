#!/usr/bin/env python3
"""Fail when production Swift string literals still contain Chinese text."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SWIFT_ROOTS = (ROOT / "gitrelay", ROOT / "GitRelayCore")
SPECIAL_FREQUENCY_FILES = {"SyncFrequency.swift", "VerificationFrequency.swift"}
HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
# Overlapping matches include literals nested in Swift interpolation
# expressions, whose opening quote can also terminate an outer match.
STRING_LITERAL_RE = re.compile(r'(?="((?:\\.|[^"\\])*)")')
ALLOWED_CASE_RE = re.compile(
    r'^\s*case\s+\w+\s*=\s*"[^"]*[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff][^"]*"\s*(?://.*)?$'
)


def main() -> int:
    violations: list[tuple[Path, int, str]] = []
    files = sorted(path for root in SWIFT_ROOTS for path in root.rglob("*.swift"))

    for path in files:
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            chinese = [
                match.group(1)
                for match in STRING_LITERAL_RE.finditer(line)
                if HAN_RE.search(match.group(1))
            ]
            if not chinese:
                continue
            if (
                path.name in SPECIAL_FREQUENCY_FILES
                and ALLOWED_CASE_RE.fullmatch(line)
            ):
                continue
            violations.extend((path, line_number, literal) for literal in chinese)

    if violations:
        print(f"Found {len(violations)} unlocalized Chinese string literal(s):")
        for path, line_number, literal in violations:
            print(f"{path.relative_to(ROOT)}:{line_number}: {literal}")
        return 1

    print(
        f"Checked {len(files)} Swift files; "
        "no unlocalized Chinese string literals found."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
