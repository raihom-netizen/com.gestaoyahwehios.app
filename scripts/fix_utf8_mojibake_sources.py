#!/usr/bin/env python3
"""Corrige mojibake UTF-8 (Latin-1 mal interpretado) em fontes Dart/TS/HTML do projeto."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Pastas com UI/strings do produto (evita tocar binários / node_modules).
SCAN_DIRS = [
    ROOT / "flutter_app" / "lib",
    ROOT / "functions" / "src",
    ROOT / "scripts",
]

EXTENSIONS = {".dart", ".ts", ".js", ".html", ".md", ".json", ".cjs", ".mjs"}

# Indicadores típicos de UTF-8 lido como Windows-1252/Latin-1.
MOJIBAKE_RE = re.compile(
    r"Ã.|Â.|â€|â†|â€œ|â€|ï¿½|Ã\u00a0|[\x80-\x9f]"
)


def looks_like_mojibake(text: str) -> bool:
    if MOJIBAKE_RE.search(text):
        return True
    # Aspas/t travessão quebrados sem Ã explícito.
    return "â€œ" in text or "â€" in text or "â€™" in text


def repair_mojibake(text: str) -> str:
    """Repara texto com UTF-8 interpretado como Latin-1/CP1252."""
    if not looks_like_mojibake(text):
        return text
    for encoding in ("cp1252", "latin-1"):
        try:
            repaired = text.encode(encoding).decode("utf-8")
            if repaired != text:
                return repaired
        except (UnicodeDecodeError, UnicodeEncodeError):
            continue
    return text


def repair_line(line: str) -> str:
    if not looks_like_mojibake(line):
        return line
    fixed = repair_mojibake(line)
    # Dupla codificação ocasional — segunda passagem.
    if looks_like_mojibake(fixed):
        fixed2 = repair_mojibake(fixed)
        if fixed2 != fixed:
            fixed = fixed2
    return fixed


def process_file(path: Path, dry_run: bool) -> bool:
    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        original = path.read_text(encoding="latin-1")

    if not looks_like_mojibake(original):
        return False

    lines = original.splitlines(keepends=True)
    changed = False
    new_lines: list[str] = []
    for line in lines:
        fixed = repair_line(line.rstrip("\n\r"))
        suffix = line[len(line.rstrip("\n\r")) :]
        new_line = fixed + suffix
        if new_line != line:
            changed = True
        new_lines.append(new_line)

    if not changed:
        # Tentativa no arquivo inteiro (comentários multilinha raros).
        whole = repair_mojibake(original)
        if whole != original and not looks_like_mojibake(whole):
            changed = True
            new_content = whole
        else:
            return False
    else:
        new_content = "".join(new_lines)

    if dry_run:
        print(f"[dry-run] would fix: {path.relative_to(ROOT)}")
        return True

    path.write_text(new_content, encoding="utf-8", newline="\n")
    print(f"fixed: {path.relative_to(ROOT)}")
    return True


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    fixed_count = 0
    for base in SCAN_DIRS:
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix.lower() not in EXTENSIONS:
                continue
            if "node_modules" in path.parts or ".git" in path.parts:
                continue
            if process_file(path, dry_run):
                fixed_count += 1

    print(f"\nTotal: {fixed_count} arquivo(s) {'a corrigir' if dry_run else 'corrigido(s)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
