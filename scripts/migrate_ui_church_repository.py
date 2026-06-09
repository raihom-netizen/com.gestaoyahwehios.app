#!/usr/bin/env python3
"""Migra telas: ChurchOperationalPaths.churchDoc(...).collection('x') → ChurchUiCollections."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_app" / "lib" / "ui"

COL_MAP = {
    "membros": "membros",
    "members": "membros",  # legado → canónico
    "departamentos": "departamentos",
    "cargos": "cargos",
    "eventos": "eventos",
    "noticias": "eventos",
    "avisos": "avisos",
    "chats": "chats",
    "patrimonio": "patrimonio",
    "finance": "financeiro",
    "financeiro": "financeiro",
    "fornecedores": "fornecedores",
    "escalas": "escalas",
    "agenda": "agenda",
    "lideres": "lideres",
    "administrativo": "administrativo",
    "doacoes": "doacoes",
    "mercadopago": "mercadopago",
    "cartoes": "cartoes",
    "certificados_emitidos": "certificados",
    "certificados": "certificados",
    "pedidosOracao": "pedidosOracao",
    "cartas_historico": "transferencias",
    "visitantes": "visitantes",
    "config": "config",
}

IMPORT_LINE = (
    "import 'package:gestao_yahweh/core/data/church_ui_collections.dart';\n"
)

CHURCH_DOC_RE = re.compile(
    r"ChurchOperationalPaths\.churchDoc\(([^)]+)\)",
    re.MULTILINE,
)

CHAIN_RE = re.compile(
    r"ChurchOperationalPaths\.churchDoc\(([^)]+)\)\s*"
    r"(?:\.\s*)?\.collection\(\s*['\"]([^'\"]+)['\"]\s*\)",
    re.MULTILINE,
)

CHURCH_REPO_DOC_RE = re.compile(
    r"(?<!UiCollections\.)ChurchRepository\.churchDoc\(",
)


def ensure_import(text: str) -> str:
    if "church_ui_collections.dart" in text:
        return text
    if "church_repository.dart" in text:
        return text.replace(
            "import 'package:gestao_yahweh/core/repositories/church_repository.dart';\n",
            "import 'package:gestao_yahweh/core/repositories/church_repository.dart';\n"
            + IMPORT_LINE,
            1,
        )
    # insert after first import block
    lines = text.splitlines(keepends=True)
    idx = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            idx = i + 1
    lines.insert(idx, IMPORT_LINE)
    return "".join(lines)


def migrate_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    text = original

    def repl_chain(m: re.Match) -> str:
        tid = m.group(1).strip()
        col = m.group(2).strip()
        helper = COL_MAP.get(col)
        if not helper:
            return m.group(0)
        return f"ChurchUiCollections.{helper}({tid})"

    text = CHAIN_RE.sub(repl_chain, text)

    # churchDoc alone → ChurchUiCollections.churchDoc
    text = CHURCH_DOC_RE.sub(r"ChurchUiCollections.churchDoc(\1)", text)

    if text == original:
        return False

    text = ensure_import(text)
    path.write_text(text, encoding="utf-8")
    return True


def main() -> int:
    changed = 0
    for dart in sorted(ROOT.rglob("*.dart")):
        if migrate_file(dart):
            changed += 1
            print(dart.relative_to(ROOT.parent.parent))
    print(f"Migrated {changed} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
