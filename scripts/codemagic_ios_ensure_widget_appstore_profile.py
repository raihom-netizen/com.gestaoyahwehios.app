#!/usr/bin/env python3
"""
Cria/baixa perfil IOS_APP_STORE só da extensão Widget — SEM fetch-signing-files.

Motivo: `app-store-connect fetch-signing-files --create` tenta gravar o certificado
Distribution e falha com:
  "Cannot save Signing Certificates without certificate private key"
quando o CI usa P12 (CM_CERTIFICATE) em vez de CERTIFICATE_PRIVATE_KEY (PEM CSR).

Este script:
  - reutiliza o Apple Distribution do P12 (/tmp/cm_distribution.p12) já instalado;
  - cria/baixa só o .mobileprovision do WIDGET_BUNDLE_ID via REST;
  - NÃO sobrescreve /tmp/cm_prov.plist nem /tmp/cm_raw.mobileprovision (perfil do app).
"""
from __future__ import annotations

import base64
import os
import plistlib
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import codemagic_ios_asc_api_ensure_appstore_profile as asc  # noqa: E402

WIDGET_BUNDLE = os.environ.get(
    "WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget"
).strip()
APP_GROUP = (
    os.environ.get("APP_GROUP_ID") or "group.com.gestaoyahwehios.app.widget"
).strip()
P12 = "/tmp/cm_distribution.p12"


def _install_widget_profile(raw: bytes) -> tuple[str, str]:
    """Grava só em Library/MobileDevice — não toca nos ficheiros /tmp do Runner."""
    prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(prov_dir, exist_ok=True)
    tmp = "/tmp/_cm_widget_raw.mobileprovision"
    with open(tmp, "wb") as f:
        f.write(raw)
    r = subprocess.run(
        ["security", "cms", "-D", "-i", tmp],
        capture_output=True,
        check=False,
    )
    if r.returncode != 0:
        raise RuntimeError("Falha ao descodificar perfil Widget (security cms -D).")
    pl = plistlib.loads(r.stdout)
    uuid = str(pl.get("UUID") or "")
    name = str(pl.get("Name") or "")
    if not uuid:
        raise RuntimeError("Perfil Widget sem UUID.")
    dest = os.path.join(prov_dir, f"{uuid}.mobileprovision")
    with open(dest, "wb") as f:
        f.write(raw)
    os.chmod(dest, 0o600)
    groups = (pl.get("Entitlements") or {}).get(
        "com.apple.security.application-groups"
    ) or []
    print(f"OK: perfil Widget instalado: {name} ({uuid})")
    print(f"  bundle esperado: {WIDGET_BUNDLE}")
    print(f"  application-groups: {groups}")
    if APP_GROUP and APP_GROUP not in groups:
        raise RuntimeError(
            f"Perfil Widget sem App Group {APP_GROUP}. "
            "Confirme o passo «Ativar App Groups» e apague perfis antigos."
        )
    return name, uuid


def main() -> int:
    print("=== Perfil App Store do Widget (API REST, sem gravar certificado) ===")
    print(f"WIDGET_BUNDLE_ID={WIDGET_BUNDLE}")
    print(f"APP_GROUP_ID={APP_GROUP}")

    if not WIDGET_BUNDLE:
        print("ERRO: WIDGET_BUNDLE_ID vazio.", file=sys.stderr)
        return 1
    if not os.path.isfile(P12):
        print(
            f"ERRO: {P12} ausente — rode antes o passo de instalar P12/perfil do app.",
            file=sys.stderr,
        )
        return 1

    pw = asc._resolve_p12_password()
    try:
        der = asc._p12_leaf_der(P12, pw)
        fp_p12 = asc._fp_sha256_der(der)
    except Exception as e:
        print(f"ERRO: ler P12: {e}", file=sys.stderr)
        return 1
    if not fp_p12:
        print("ERRO: fingerprint P12 vazio.", file=sys.stderr)
        return 1

    try:
        token = asc._ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT ASC: {e}", file=sys.stderr)
        return 1

    certs = asc._list_distribution_certificates(token)
    match = asc._find_cert_for_p12(fp_p12, der, certs)
    if not match:
        print(
            "ERRO: nenhum Apple Distribution na ASC corresponde ao P12 (SHA256).",
            file=sys.stderr,
        )
        print(f"  P12 SHA256: {fp_p12}", file=sys.stderr)
        return 1
    cert_id = str(match["id"])
    print(f"Cert Distribution (P12): id={cert_id}")

    bundle_rid = asc._find_bundle_id(token, WIDGET_BUNDLE)
    if not bundle_rid:
        print(
            f"ERRO: Bundle ID Widget não encontrado na ASC: {WIDGET_BUNDLE}",
            file=sys.stderr,
        )
        print(
            "  O passo «Ativar App Groups» deve criar o App ID da extensão.",
            file=sys.stderr,
        )
        return 1
    print(f"Bundle Widget resource id: {bundle_rid}")

    # 1) Reutilizar perfil existente com o mesmo cert + App Group
    for pr in asc._profiles_for_bundle(token, bundle_rid):
        attr = pr.get("attributes") or {}
        if str(attr.get("profileType") or "") != "IOS_APP_STORE":
            continue
        pid = str(pr.get("id") or "")
        if not pid or not asc._profile_includes_certificate(token, pid, cert_id):
            continue
        raw = asc._download_profile_content(token, pid)
        if not raw:
            continue
        if APP_GROUP and not asc._raw_profile_has_app_group(raw, APP_GROUP):
            print(
                f"AVISO: perfil Widget id={pid} sem App Group — ignorar e criar novo."
            )
            continue
        try:
            _install_widget_profile(raw)
            return 0
        except Exception as e:
            print(f"AVISO: instalar perfil existente falhou: {e}", file=sys.stderr)

    # 2) Criar perfil novo (capabilities atuais do App ID, incl. App Groups)
    unique = f"GestaoYahwehWidget_{int(time.time())}"
    print(f"A criar perfil IOS_APP_STORE: {unique}")
    created = asc._create_app_store_profile(
        token, bundle_rid, cert_id, WIDGET_BUNDLE, unique
    )
    if not created:
        print("ERRO: POST profiles (Widget) falhou.", file=sys.stderr)
        return 1

    raw: bytes | None = None
    inline = created.get("_inline_profileContent")
    if isinstance(inline, str) and inline:
        try:
            raw = base64.b64decode(inline)
        except Exception:
            raw = None
    if not raw:
        new_id = str(created.get("id") or "")
        if new_id:
            raw = asc._download_profile_content(token, new_id)
    if not raw:
        print("ERRO: perfil Widget criado sem profileContent.", file=sys.stderr)
        return 1

    try:
        _install_widget_profile(raw)
    except Exception as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"ERRO: ensure widget profile: {e}", file=sys.stderr)
        raise SystemExit(1)
