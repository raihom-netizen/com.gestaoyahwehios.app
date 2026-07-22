#!/usr/bin/env python3
"""
Cria/baixa perfil IOS_APP_STORE só da extensão Widget — SEM fetch-signing-files.

Evita: "Cannot save Signing Certificates without certificate private key".

Resolve o certificado Distribution nesta ordem:
  1) /tmp/cm_distribution.p12 (modo manual)
  2) outros P12 temporários do CI (api_only)
  3) recriar P12 a partir de CM_CERTIFICATE / CERTIFICATE_PRIVATE_KEY (Base64)
  4) leaf DER em /tmp/cm_prov.plist (perfil do Runner já instalado)
  5) PEM Distribution nos secrets (match SPKI na ASC)

NÃO sobrescreve /tmp/cm_prov.plist nem /tmp/cm_raw.mobileprovision do app.
"""
from __future__ import annotations

import base64
import os
import plistlib
import re
import shutil
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

P12_CANDIDATES = (
    "/tmp/cm_distribution.p12",
    "/tmp/cm_api_only_identity.p12",
    "/tmp/cm_api_only_from_secret.p12",
    "/tmp/_cm_verify_p12.bin",
)


def _install_widget_profile(raw: bytes) -> tuple[str, str]:
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


def _looks_like_pem(raw: str) -> bool:
    return bool(re.search(r"BEGIN (EC |RSA )?PRIVATE KEY", raw or ""))


def _materialize_p12_from_secrets() -> str | None:
    """Recria /tmp/cm_distribution.p12 a partir do secret Base64 (se for P12)."""
    raw = (os.environ.get("CM_CERTIFICATE") or os.environ.get("CERTIFICATE_PRIVATE_KEY") or "").strip()
    if not raw or _looks_like_pem(raw):
        return None
    b64 = "".join(raw.split())
    try:
        data = base64.b64decode(b64, validate=False)
    except Exception:
        return None
    if not data or len(data) < 64:
        return None
    out = "/tmp/cm_distribution.p12"
    with open(out, "wb") as f:
        f.write(data)
    os.chmod(out, 0o600)
    print(f"OK: P12 recriado a partir do secret → {out} ({len(data)} bytes)")
    return out


def _first_existing_p12() -> str | None:
    for path in P12_CANDIDATES:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            print(f"OK: a usar P12 existente: {path}")
            if path != "/tmp/cm_distribution.p12":
                try:
                    shutil.copyfile(path, "/tmp/cm_distribution.p12")
                    os.chmod("/tmp/cm_distribution.p12", 0o600)
                except OSError:
                    pass
            return path if os.path.isfile(path) else "/tmp/cm_distribution.p12"
    return _materialize_p12_from_secrets()


def _cert_id_from_p12(token: str, p12_path: str) -> str | None:
    pw = asc._resolve_p12_password()
    try:
        der = asc._p12_leaf_der(p12_path, pw)
        fp = asc._fp_sha256_der(der)
    except Exception as e:
        print(f"AVISO: ler P12 {p12_path}: {e}", file=sys.stderr)
        return None
    if not fp:
        return None
    certs = asc._list_distribution_certificates(token)
    match = asc._find_cert_for_p12(fp, der, certs)
    if not match:
        print(f"AVISO: P12 SHA256={fp} sem match na ASC.", file=sys.stderr)
        return None
    return str(match["id"])


def _cert_id_from_runner_profile(token: str) -> str | None:
    """Usa DeveloperCertificates do perfil do Runner já instalado."""
    plist_paths = (
        "/tmp/cm_prov.plist",
        "/tmp/cm_widget_probe.plist",
    )
    # Também tenta o primeiro .mobileprovision do bundle principal.
    main_bundle = (
        os.environ.get("BUNDLE_ID")
        or os.environ.get("IOS_BUNDLE_ID")
        or "com.gestaoyahwehios.app"
    ).strip()
    for path, pl in _iter_local_profiles():
        ent = pl.get("Entitlements") or {}
        app_id = str(ent.get("application-identifier") or "")
        if main_bundle and not app_id.endswith(main_bundle):
            continue
        for item in pl.get("DeveloperCertificates") or []:
            if not isinstance(item, (bytes, bytearray)):
                continue
            der = bytes(item)
            fp = asc._fp_sha256_der(der)
            if not fp:
                continue
            certs = asc._list_distribution_certificates(token)
            match = asc._find_cert_for_p12(fp, der, certs)
            if match:
                print(f"OK: cert Distribution via perfil Runner ({path}) id={match['id']}")
                return str(match["id"])
    for plist_path in plist_paths:
        if not os.path.isfile(plist_path):
            continue
        try:
            with open(plist_path, "rb") as f:
                pl = plistlib.load(f)
        except Exception:
            continue
        for item in pl.get("DeveloperCertificates") or []:
            if not isinstance(item, (bytes, bytearray)):
                continue
            der = bytes(item)
            fp = asc._fp_sha256_der(der)
            if not fp:
                continue
            certs = asc._list_distribution_certificates(token)
            match = asc._find_cert_for_p12(fp, der, certs)
            if match:
                print(f"OK: cert Distribution via {plist_path} id={match['id']}")
                return str(match["id"])
    return None


def _iter_local_profiles() -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    for d in (
        os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
        os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles"),
    ):
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            if not name.endswith(".mobileprovision"):
                continue
            path = os.path.join(d, name)
            r = subprocess.run(
                ["security", "cms", "-D", "-i", path],
                capture_output=True,
                check=False,
            )
            if r.returncode != 0:
                continue
            try:
                out.append((path, plistlib.loads(r.stdout)))
            except Exception:
                continue
    return out


def _cert_id_from_pem(token: str) -> str | None:
    priv = asc._load_distribution_private_key_from_env()
    if priv is None:
        return None
    certs = asc._list_distribution_certificates(token)
    cert_id = asc._find_cert_id_for_privkey(priv, certs)
    if cert_id:
        print(f"OK: cert Distribution via PEM secret id={cert_id}")
    return cert_id


def _resolve_distribution_cert_id(token: str) -> str | None:
    p12 = _first_existing_p12()
    if p12:
        cid = _cert_id_from_p12(token, p12)
        if cid:
            print(f"OK: cert Distribution via P12 id={cid}")
            return cid
    cid = _cert_id_from_runner_profile(token)
    if cid:
        return cid
    return _cert_id_from_pem(token)


def main() -> int:
    print("=== Perfil App Store do Widget (API REST, sem gravar certificado) ===")
    print(f"WIDGET_BUNDLE_ID={WIDGET_BUNDLE}")
    print(f"APP_GROUP_ID={APP_GROUP}")
    mode = ""
    if os.path.isfile("/tmp/cm_yw_signing_mode"):
        mode = open("/tmp/cm_yw_signing_mode", encoding="utf-8").read().strip()
        print(f"signing_mode={mode or '(vazio)'}")

    if not WIDGET_BUNDLE:
        print("ERRO: WIDGET_BUNDLE_ID vazio.", file=sys.stderr)
        return 1

    try:
        token = asc._ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT ASC: {e}", file=sys.stderr)
        return 1

    cert_id = _resolve_distribution_cert_id(token)
    if not cert_id:
        print(
            "ERRO: não foi possível identificar o Apple Distribution "
            "(sem P12 em /tmp, sem perfil Runner, sem PEM).",
            file=sys.stderr,
        )
        print("  Dica: confirme CM_CERTIFICATE (P12) ou perfil do app no passo anterior.", file=sys.stderr)
        return 1

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
    print(f"Cert Distribution id: {cert_id}")

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
