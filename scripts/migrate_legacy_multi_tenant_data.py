#!/usr/bin/env python3
"""Migração segura de dados legados para estrutura multi-tenant canônica.

Foco:
- Coleções salvas na raiz do Firestore (ex.: /membros, /finance, /patrimonio).
- Documentos gravados sob tenant fixo legado (ex.: igreja_o_brasil_para_cristo_jardim_goiano)
  mas cujo payload aponta para outro tenant em campos internos.

Modo padrão: DRY-RUN (não escreve, não apaga).
Para aplicar: --apply
"""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from typing import Any, Dict, Iterable, Optional

import firebase_admin
from firebase_admin import credentials, firestore

from firebase_paths import FirebasePaths


ROOT_COLLECTION = "igrejas"
LEGACY_FIXED_CHURCH = "igreja_o_brasil_para_cristo_jardim_goiano"


ROOT_COLLECTION_MAPPINGS: dict[str, str] = {
    "membros": "membros",
    "members": "membros",
    "departamentos": "departamentos",
    "visitantes": "visitantes",
    "cargos": "cargos",
    "mural_avisos": "mural_avisos",
    "avisos": "avisos",
    "chats": "chats",
    "escalas": "escalas",
    "certificados": "certificados",
    "finance": "finance",
    "financeiro": "finance",
    "finance_logs": "finance_logs",
    "finance_mp_notifications": "finance_mp_notifications",
    "fornecedores": "fornecedores",
    "fornecedor_compromissos": "fornecedor_compromissos",
    "patrimonio": "patrimonio",
}


LEGACY_SUBCOLLECTIONS_TO_CHECK = sorted(set(ROOT_COLLECTION_MAPPINGS.values()))

TENANT_FIELD_CANDIDATES = (
    "churchId",
    "tenantId",
    "igrejaId",
    "church_id",
    "tenant_id",
)


@dataclass
class Stats:
    inspected: int = 0
    moved: int = 0
    skipped: int = 0
    errors: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Migra dados legados para paths canônicos por churchId."
    )
    parser.add_argument(
        "--credentials",
        default=os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip(),
        help="Caminho do JSON da service account.",
    )
    parser.add_argument(
        "--project-id",
        default=os.getenv("FIREBASE_PROJECT_ID", "").strip(),
        help="Project ID Firebase (opcional se presente no JSON).",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Aplica alterações (sem isto, roda apenas em dry-run).",
    )
    parser.add_argument(
        "--scan-fixed-church",
        default=LEGACY_FIXED_CHURCH,
        help="Church fixo legado para auditar subcoleções inconsistentes.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limite global de documentos processados (0 = sem limite).",
    )
    parser.add_argument(
        "--never-delete-subcollections",
        default="membros",
        help=(
            "Lista separada por vírgula de subcoleções cuja origem nunca será apagada "
            "mesmo em --apply (padrão: membros)."
        ),
    )
    return parser.parse_args()


def init_firestore(credentials_path: str, project_id: str) -> firestore.Client:
    if not credentials_path:
        raise ValueError(
            "Informe --credentials ou defina GOOGLE_APPLICATION_CREDENTIALS."
        )
    if not os.path.exists(credentials_path):
        raise FileNotFoundError(f"Credencial não encontrada: {credentials_path}")

    cred = credentials.Certificate(credentials_path)
    if firebase_admin._apps:
        app = firebase_admin.get_app()
    else:
        kwargs: Dict[str, Any] = {}
        if project_id:
            kwargs["projectId"] = project_id
        app = firebase_admin.initialize_app(cred, kwargs)
    return firestore.client(app=app)


def normalize_church_id(raw: Any) -> str:
    value = str(raw or "").strip()
    if not value:
        return ""
    value = value.replace("\\", "/")
    while "//" in value:
        value = value.replace("//", "/")

    if value.startswith(f"{ROOT_COLLECTION}/"):
        # igrejas/{churchId}/...
        parts = value.split("/")
        if len(parts) >= 2:
            value = parts[1].strip()

    if value.startswith("/"):
        value = value[1:]
    if value.startswith(f"{ROOT_COLLECTION}/"):
        parts = value.split("/")
        if len(parts) >= 2:
            value = parts[1].strip()

    if value.startswith("v_igreja_"):
        value = value[len("v_") :]
    if value.startswith("id_igreja_"):
        value = value[len("id_") :]

    return value.strip()


def infer_church_id(data: Dict[str, Any]) -> str:
    for field in TENANT_FIELD_CANDIDATES:
        resolved = normalize_church_id(data.get(field))
        if resolved:
            return resolved
    return ""


def target_doc_path(church_id: str, target_subcollection: str, doc_id: str) -> str:
    return f"{FirebasePaths.igreja(church_id)}/{target_subcollection}/{doc_id}"


def maybe_stop(stats: Stats, limit: int) -> bool:
    return limit > 0 and stats.inspected >= limit


def migrate_doc(
    db: firestore.Client,
    *,
    source_ref: firestore.DocumentReference,
    source_path: str,
    source_data: Dict[str, Any],
    target_subcollection: str,
    never_delete_subcollections: set[str],
    apply_changes: bool,
    stats: Stats,
) -> None:
    stats.inspected += 1
    church_id = infer_church_id(source_data)
    if not church_id:
        stats.skipped += 1
        print(f"[SKIP] sem churchId/tenantId | {source_path}")
        return

    destination = target_doc_path(church_id, target_subcollection, source_ref.id)
    if destination == source_path:
        stats.skipped += 1
        print(f"[SKIP] origem já canónica | {source_path}")
        return

    print(f"[MOVE] {source_path} -> {destination}")
    if not apply_changes:
        stats.moved += 1
        return

    try:
        target_ref = db.document(destination)
        target_ref.set(source_data, merge=True)
        if not target_ref.get().exists:
            raise RuntimeError("Falha na verificação pós-escrita (target inexistente).")
        if target_subcollection in never_delete_subcollections:
            print(
                f"[SAFE-KEEP] origem preservada para '{target_subcollection}' | {source_path}"
            )
        else:
            source_ref.delete()
        stats.moved += 1
    except Exception as exc:  # pylint: disable=broad-except
        stats.errors += 1
        print(f"[ERROR] {source_path} -> {destination} | {exc}")


def stream_docs(col_ref: firestore.CollectionReference) -> Iterable[Any]:
    # stream() evita leitura total em memória e funciona bem para coleções grandes.
    return col_ref.stream()


def migrate_root_collections(
    db: firestore.Client,
    apply_changes: bool,
    limit: int,
    stats: Stats,
    never_delete_subcollections: set[str],
) -> None:
    print("\n=== Fase 2A: coleções raiz legadas ===")
    for source_collection, target_subcollection in ROOT_COLLECTION_MAPPINGS.items():
        if maybe_stop(stats, limit):
            break
        col_ref = db.collection(source_collection)
        print(f"\n[SCAN] /{source_collection} -> /igrejas/{{churchId}}/{target_subcollection}")
        for snap in stream_docs(col_ref):
            if maybe_stop(stats, limit):
                break
            data = snap.to_dict() or {}
            migrate_doc(
                db,
                source_ref=snap.reference,
                source_path=snap.reference.path,
                source_data=data,
                target_subcollection=target_subcollection,
                never_delete_subcollections=never_delete_subcollections,
                apply_changes=apply_changes,
                stats=stats,
            )


def migrate_fixed_church_misplaced_docs(
    db: firestore.Client,
    fixed_church_id: str,
    apply_changes: bool,
    limit: int,
    stats: Stats,
    never_delete_subcollections: set[str],
) -> None:
    if not fixed_church_id.strip():
        return

    print("\n=== Fase 2B: varredura do tenant fixo legado ===")
    church_doc = db.collection(ROOT_COLLECTION).document(fixed_church_id.strip())
    for subcollection in LEGACY_SUBCOLLECTIONS_TO_CHECK:
        if maybe_stop(stats, limit):
            break
        col_ref = church_doc.collection(subcollection)
        print(f"\n[SCAN] /{church_doc.path}/{subcollection}")
        for snap in stream_docs(col_ref):
            if maybe_stop(stats, limit):
                break
            data = snap.to_dict() or {}
            inferred = infer_church_id(data)
            if not inferred or inferred == fixed_church_id:
                stats.inspected += 1
                stats.skipped += 1
                continue
            migrate_doc(
                db,
                source_ref=snap.reference,
                source_path=snap.reference.path,
                source_data=data,
                target_subcollection=subcollection,
                never_delete_subcollections=never_delete_subcollections,
                apply_changes=apply_changes,
                stats=stats,
            )


def print_summary(stats: Stats, apply_changes: bool) -> None:
    mode = "APPLY" if apply_changes else "DRY-RUN"
    print("\n=== Resumo da migração ===")
    print(f"Modo: {mode}")
    print(f"Inspecionados: {stats.inspected}")
    print(f"Movidos: {stats.moved}")
    print(f"Ignorados: {stats.skipped}")
    print(f"Erros: {stats.errors}")


def main() -> None:
    args = parse_args()
    stats = Stats()
    db = init_firestore(args.credentials, args.project_id)
    never_delete_subcollections = {
        p.strip() for p in args.never_delete_subcollections.split(",") if p.strip()
    }
    print(
        "Iniciando migração "
        f"({'APPLY' if args.apply else 'DRY-RUN'}) para Firestore multi-tenant canônico..."
    )
    if never_delete_subcollections:
        print(
            "Proteção ativa de não exclusão para subcoleções: "
            + ", ".join(sorted(never_delete_subcollections))
        )
    migrate_root_collections(
        db,
        args.apply,
        args.limit,
        stats,
        never_delete_subcollections,
    )
    migrate_fixed_church_misplaced_docs(
        db,
        fixed_church_id=args.scan_fixed_church,
        apply_changes=args.apply,
        limit=args.limit,
        stats=stats,
        never_delete_subcollections=never_delete_subcollections,
    )
    print_summary(stats, args.apply)


if __name__ == "__main__":
    main()

