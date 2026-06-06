#!/usr/bin/env python3
"""Migra .snapshots() directo para .watchSafe() (FirestoreStreamUtils)."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_app" / "lib"
IMPORT_LINE = (
    "import 'package:gestao_yahweh/services/firestore_stream_utils.dart';"
)
SKIP_PARTS = (
    "firestore_stream_utils.dart",
    ".dart_tool",
)

REDUNDANT_RESILIENT_QUERY = re.compile(
    r"FirestoreStreamUtils\.resilientQuery\(\s*([\s\S]*?)\.watchSafe\(\)\s*\)",
    re.MULTILINE,
)
REDUNDANT_RESILIENT_DOC = re.compile(
    r"FirestoreStreamUtils\.resilientDocument\(\s*([\s\S]*?)\.watchSafe\(\)\s*\)",
    re.MULTILINE,
)


def should_skip(path: Path) -> bool:
    s = str(path).replace("\\", "/")
    return any(part in s for part in SKIP_PARTS)


def ensure_import(content: str) -> str:
    if IMPORT_LINE in content:
        return content
    if ".watchSafe(" not in content:
        return content
    lines = content.splitlines(keepends=True)
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, IMPORT_LINE + "\n")
    return "".join(lines)


def migrate_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    if ".snapshots()" not in original and ".watchSafe(" not in original:
        return False

    content = original
    if ".snapshots()" in content and "firestore_stream_utils.dart" not in str(path):
        content = content.replace(".snapshots()", ".watchSafe()")

    prev = None
    while prev != content:
        prev = content
        content = REDUNDANT_RESILIENT_QUERY.sub(r"\1.watchSafe()", content)
        content = REDUNDANT_RESILIENT_DOC.sub(r"\1.watchSafe()", content)

    content = ensure_import(content)
    if content != original:
        path.write_text(content, encoding="utf-8")
        return True
    return False


def main() -> None:
    changed = 0
    for path in sorted(ROOT.rglob("*.dart")):
        if should_skip(path):
            continue
        if migrate_file(path):
            changed += 1
            print(f"OK {path.relative_to(ROOT.parent.parent)}")
    print(f"\nMigrated {changed} files.")


if __name__ == "__main__":
    main()
