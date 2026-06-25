#!/usr/bin/env python3
"""Migração segura de objetos Firebase Storage legados para paths canónicos.

Origens típicas:
- `tenants/{tenantId}/media/...` (EcoFire legado)
- `tenants/{tenantId}/...` (prefixo legado genérico)
- `igrejas/{id}/branding/`, `comprovantes/` (layouts antigos dentro da igreja)

Destino: `igrejas/{churchId}/...` conforme [FirebasePaths] / ChurchStorageLayout.

Modo padrão: DRY-RUN. Para aplicar: --apply
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from typing import Optional

import firebase_admin
from firebase_admin import credentials
from google.cloud import storage as gcs

from firebase_paths import FirebasePaths

DEFAULT_BUCKET = "gestaoyahweh-21e23.firebasestorage.app"
SKIP_PREFIXES = ("public/", "igrejas/")


@dataclass
class Stats:
    inspected: int = 0
    moved: int = 0
    skipped: int = 0
    errors: int = 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Migra objetos Storage legados para igrejas/{churchId}/…"
    )
    parser.add_argument(
        "--credentials",
        default=os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip(),
        help="Caminho do JSON da service account.",
    )
    parser.add_argument(
        "--bucket",
        default=os.getenv("FIREBASE_STORAGE_BUCKET", DEFAULT_BUCKET).strip(),
        help="Bucket Firebase Storage.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Copia objetos e apaga origem (sem isto = dry-run).",
    )
    parser.add_argument(
        "--prefix",
        default="tenants/",
        help="Prefixo inicial a varrer (padrão: tenants/).",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limite de objetos processados (0 = sem limite).",
    )
    parser.add_argument(
        "--never-delete-prefixes",
        default="membros/",
        help="Prefixos relativos à igreja cuja origem nunca será apagada.",
    )
    return parser.parse_args()


def init_gcs_client(credentials_path: str) -> gcs.Client:
    if not credentials_path:
        raise ValueError(
            "Informe --credentials ou defina GOOGLE_APPLICATION_CREDENTIALS."
        )
    if not os.path.exists(credentials_path):
        raise FileNotFoundError(f"Credencial não encontrada: {credentials_path}")
    if not firebase_admin._apps:
        cred = credentials.Certificate(credentials_path)
        firebase_admin.initialize_app(cred)
    return gcs.Client.from_service_account_json(credentials_path)


def normalize_church_id(raw: str) -> str:
    value = (raw or "").strip().replace("\\", "/")
    if value.startswith("v_igreja_"):
        value = value[len("v_") :]
    if value.startswith("id_igreja_"):
        value = value[len("id_") :]
    return value.strip()


def _safe_doc_id(value: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9_-]", "_", (value or "").strip())
    s = re.sub(r"_+", "_", s)
    return s or "doc"


def canonical_destination(source_path: str) -> Optional[str]:
    """Traduz path físico legado para path canónico. None = ignorar."""
    p = source_path.strip().lstrip("/")
    if not p or p.startswith(SKIP_PREFIXES):
        return None

    # tenants/{tid}/media/avisos/images/{postId}/capa_aviso.webp
    m = re.match(
        r"^tenants/([^/]+)/media/avisos/images/([^/]+)/capa_aviso\.webp$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        return FirebasePaths.storage_aviso_photo(tid, post_id, 0)

    m = re.match(
        r"^tenants/([^/]+)/media/avisos/images/([^/]+)/galeria_(\d+)\.webp$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        slot = int(m.group(3) or "1")
        return FirebasePaths.storage_aviso_photo(tid, post_id, slot)

    m = re.match(
        r"^tenants/([^/]+)/media/eventos/images/([^/]+)/banner_evento\.webp$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        return FirebasePaths.storage_evento_photo(tid, post_id, 0)

    m = re.match(
        r"^tenants/([^/]+)/media/eventos/images/([^/]+)/galeria_(\d+)\.webp$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        slot = int(m.group(3) or "1")
        return FirebasePaths.storage_evento_photo(tid, post_id, slot)

    m = re.match(
        r"^tenants/([^/]+)/media/eventos/videos/([^/]+)_v(\d)\.mp4$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        slot = int(m.group(3) or "0")
        return FirebasePaths.storage_evento_video(tid, post_id, slot)

    m = re.match(
        r"^tenants/([^/]+)/media/eventos/videos/([^/]+)_v(\d)_thumb\.jpg$",
        p,
    )
    if m:
        tid, post_id = normalize_church_id(m.group(1)), m.group(2)
        slot = int(m.group(3) or "0")
        return FirebasePaths.storage_evento_video_thumb(tid, post_id, slot)

    # tenants/{tid}/... genérico → igrejas/{tid}/...
    m = re.match(r"^tenants/([^/]+)/(.+)$", p)
    if m:
        tid = normalize_church_id(m.group(1))
        rest = m.group(2)
        if rest.startswith("media/"):
            rest = rest[len("media/") :]
        return f"{FirebasePaths.storage_root(tid)}/{rest}"

    # igrejas/{id}/branding/logo_igreja.jpg → configuracoes/logo_igreja.png
    m = re.match(r"^igrejas/([^/]+)/branding/logo_igreja\.(jpg|png)$", p)
    if m:
        tid = normalize_church_id(m.group(1))
        return FirebasePaths.storage_logo(tid)

    # igrejas/{id}/comprovantes/{lancamentoId}.jpg → financeiro (sem data — mantém nome)
    m = re.match(r"^igrejas/([^/]+)/comprovantes/([^/]+)\.(\w+)$", p)
    if m:
        tid = normalize_church_id(m.group(1))
        lid = _safe_doc_id(m.group(2))
        ext = m.group(3)
        return f"{FirebasePaths.storage_root(tid)}/financeiro/legacy/{lid}.{ext}"

    return None


def should_never_delete(source_path: str, never_delete_prefixes: set[str]) -> bool:
    for rel in never_delete_prefixes:
        if not rel:
            continue
        # relativo à pasta da igreja, ex.: membros/
        if re.search(rf"igrejas/[^/]+/{re.escape(rel.lstrip('/'))}", source_path):
            return True
    return False


def migrate_blob(
    bucket: gcs.Bucket,
    blob: gcs.Blob,
    *,
    apply_changes: bool,
    never_delete_prefixes: set[str],
    stats: Stats,
) -> None:
    stats.inspected += 1
    source = blob.name
    destination = canonical_destination(source)

    if destination is None:
        stats.skipped += 1
        return

    if destination == source:
        stats.skipped += 1
        return

    print(f"[MOVE] gs://{bucket.name}/{source} -> gs://{bucket.name}/{destination}")

    if not apply_changes:
        stats.moved += 1
        return

    try:
        bucket.copy_blob(blob, bucket, destination)
        dest_blob = bucket.blob(destination)
        if not dest_blob.exists():
            raise RuntimeError("Cópia não confirmada no destino.")
        if should_never_delete(source, never_delete_prefixes):
            print(f"[SAFE-KEEP] origem preservada | {source}")
        else:
            blob.delete()
        stats.moved += 1
    except Exception as exc:  # pylint: disable=broad-except
        stats.errors += 1
        print(f"[ERROR] {source} -> {destination} | {exc}")


def print_summary(stats: Stats, apply_changes: bool) -> None:
    mode = "APPLY" if apply_changes else "DRY-RUN"
    print("\n=== Resumo migração Storage ===")
    print(f"Modo: {mode}")
    print(f"Inspecionados: {stats.inspected}")
    print(f"Movidos: {stats.moved}")
    print(f"Ignorados: {stats.skipped}")
    print(f"Erros: {stats.errors}")


def main() -> None:
    args = parse_args()
    stats = Stats()
    client = init_gcs_client(args.credentials)
    bucket = client.bucket(args.bucket)
    never_delete = {
        p.strip() for p in args.never_delete_prefixes.split(",") if p.strip()
    }

    print(
        f"Iniciando migração Storage ({'APPLY' if args.apply else 'DRY-RUN'}) "
        f"bucket={args.bucket} prefix={args.prefix}"
    )

    for blob in client.list_blobs(bucket, prefix=args.prefix):
        if args.limit > 0 and stats.inspected >= args.limit:
            break
        migrate_blob(
            bucket,
            blob,
            apply_changes=args.apply,
            never_delete_prefixes=never_delete,
            stats=stats,
        )

    print_summary(stats, args.apply)


if __name__ == "__main__":
    main()
