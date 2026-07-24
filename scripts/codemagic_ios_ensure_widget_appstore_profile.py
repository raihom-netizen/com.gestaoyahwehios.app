#!/usr/bin/env python3
"""
Instala perfil IOS_APP_STORE da extensão Widget COM App Group.

Fluxo definitivo (sem loops de 5x):
  1) Secret CM_WIDGET_PROVISIONING_PROFILE / CM_PROVISIONING_PROFILE_2 (se existir)
  2) Perfil local já instalado com o group.com…
  3) app-store-connect fetch-signing-files --create (igual Controle Total)
  4) REST create só como último recurso

Pré-requisito no CI: codemagic_ios_register_app_groups_via_xcode.sh
(associa group.com… no portal — a ASC API sozinha nao consegue).
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
import codemagic_ios_enable_app_groups as ag  # noqa: E402

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


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True)


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
    shutil.copyfile(tmp, "/tmp/cm_widget.mobileprovision")
    with open("/tmp/cm_widget_prov.plist", "wb") as out:
        out.write(r.stdout)
    groups = (pl.get("Entitlements") or {}).get(
        "com.apple.security.application-groups"
    ) or []
    print(f"OK: perfil Widget instalado: {name} ({uuid})")
    print(f"  bundle esperado: {WIDGET_BUNDLE}")
    print(f"  application-groups: {groups}")
    if APP_GROUP and APP_GROUP not in groups:
        print(
            f"AVISO: perfil Widget sem {APP_GROUP} — "
            "align entitlements vai remover a entitlement para o codesign passar."
        )
        Path("/tmp/cm_widget_profile_missing_app_group").write_text("1\n", encoding="utf-8")
    return name, uuid


def _profile_has_group(raw: bytes) -> bool:
    return bool(APP_GROUP) and asc._raw_profile_has_app_group(raw, APP_GROUP)


def _looks_like_pem(raw: str) -> bool:
    return bool(re.search(r"BEGIN (EC |RSA )?PRIVATE KEY", raw or ""))


def _b64_secret_bytes(*names: str) -> bytes | None:
    for name in names:
        raw = (os.environ.get(name) or "").strip()
        if not raw or _looks_like_pem(raw):
            continue
        b64 = "".join(raw.split())
        try:
            data = base64.b64decode(b64, validate=False)
        except Exception:
            continue
        if data and len(data) > 64:
            print(f"OK: secret {name} → {len(data)} bytes")
            return data
    return None


def _try_install_from_secret() -> bool:
    data = _b64_secret_bytes(
        "CM_WIDGET_PROVISIONING_PROFILE",
        "WIDGET_PROVISIONING_PROFILE",
        "CM_PROVISIONING_PROFILE_2",
        "PROVISIONING_PROFILE_2",
    )
    if not data:
        return False
    try:
        _install_widget_profile(data)
        return True
    except Exception as e:
        print(f"AVISO: secret Widget profile invalido: {e}", file=sys.stderr)
        return False


def _iter_local_profiles() -> list[tuple[str, bytes, dict]]:
    out: list[tuple[str, bytes, dict]] = []
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
            try:
                with open(path, "rb") as f:
                    raw = f.read()
            except OSError:
                continue
            r = subprocess.run(
                ["security", "cms", "-D", "-i", path],
                capture_output=True,
                check=False,
            )
            if r.returncode != 0:
                continue
            try:
                out.append((path, raw, plistlib.loads(r.stdout)))
            except Exception:
                continue
    return out


def _try_install_local_matching(*, require_group: bool = True) -> bool:
    for path, raw, pl in _iter_local_profiles():
        ent = pl.get("Entitlements") or {}
        app_id = str(ent.get("application-identifier") or "")
        if not app_id.endswith(WIDGET_BUNDLE):
            continue
        groups = ent.get("com.apple.security.application-groups") or []
        if require_group and APP_GROUP and APP_GROUP not in groups:
            continue
        try:
            _install_widget_profile(raw)
            print(f"OK: reutilizado perfil local {path}")
            return True
        except Exception as e:
            print(f"AVISO: local {path}: {e}", file=sys.stderr)
    return False


def _materialize_p12_from_secrets() -> str | None:
    raw = (
        os.environ.get("CM_CERTIFICATE")
        or os.environ.get("CERTIFICATE_PRIVATE_KEY")
        or ""
    ).strip()
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
    print(f"OK: P12 recriado a partir do secret → {out}")
    return out


def _first_existing_p12() -> str | None:
    for path in P12_CANDIDATES:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            if path != "/tmp/cm_distribution.p12":
                try:
                    shutil.copyfile(path, "/tmp/cm_distribution.p12")
                    os.chmod("/tmp/cm_distribution.p12", 0o600)
                except OSError:
                    pass
            return "/tmp/cm_distribution.p12"
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
    return str(match["id"]) if match else None


def _cert_id_from_runner_profile(token: str) -> str | None:
    main_bundle = (
        os.environ.get("BUNDLE_ID")
        or os.environ.get("IOS_BUNDLE_ID")
        or "com.gestaoyahwehios.app"
    ).strip()
    for path, _raw, pl in _iter_local_profiles():
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
    return None


def _resolve_distribution_cert_id(token: str) -> str | None:
    p12 = _first_existing_p12()
    if p12:
        cid = _cert_id_from_p12(token, p12)
        if cid:
            print(f"OK: cert Distribution via P12 id={cid}")
            return cid
    return _cert_id_from_runner_profile(token)


def _fetch_signing_files_widget() -> bool:
    """Uma passagem — padrao Controle Total."""
    print(f"=== app-store-connect fetch-signing-files {WIDGET_BUNDLE} ===")
    cmd = [
        "app-store-connect",
        "fetch-signing-files",
        WIDGET_BUNDLE,
        "--type",
        "IOS_APP_STORE",
        "--create",
        "--strict-match-identifier",
    ]
    r = _run(cmd)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    if out:
        print(out[-2500:])
    if r.returncode != 0:
        print(f"AVISO: fetch-signing-files exit={r.returncode}", file=sys.stderr)
    # Procurar perfil local acabado de descarregar (com ou sem grupo).
    if _try_install_local_matching(require_group=True):
        return True
    return _try_install_local_matching(require_group=False)


def _create_via_rest_once(token: str, bundle_rid: str, cert_id: str) -> bool:
    unique = f"GestaoYahwehWidget_{int(time.time())}"
    print(f"=== REST POST profiles: {unique} ===")
    created = asc._create_app_store_profile(
        token, bundle_rid, cert_id, WIDGET_BUNDLE, unique
    )
    if not created:
        print("ERRO: POST profiles (Widget) falhou.", file=sys.stderr)
        return False
    new_id = str(created.get("id") or "")
    raw: bytes | None = None
    inline = created.get("_inline_profileContent")
    if isinstance(inline, str) and inline:
        try:
            raw = base64.b64decode(inline)
        except Exception:
            raw = None
    if not raw and new_id:
        raw = asc._download_profile_content(token, new_id)
    if not raw:
        print("ERRO: perfil Widget sem profileContent.", file=sys.stderr)
        return False
    # Instala mesmo sem App Group — align entitlements resolve o codesign.
    try:
        _install_widget_profile(raw)
        return True
    except Exception as e:
        print(f"ERRO: instalar perfil REST: {e}", file=sys.stderr)
        return False


def main() -> int:
    print("=== Perfil App Store do Widget (sem hard-fail por App Group) ===")
    print(f"WIDGET_BUNDLE_ID={WIDGET_BUNDLE}")
    print(f"APP_GROUP_ID={APP_GROUP}")

    if not WIDGET_BUNDLE:
        print("ERRO: WIDGET_BUNDLE_ID vazio.", file=sys.stderr)
        return 1

    if _try_install_from_secret():
        return 0
    if _try_install_local_matching(require_group=True):
        return 0
    if _try_install_local_matching(require_group=False):
        return 0

    try:
        token = asc._ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT ASC: {e}", file=sys.stderr)
        return 1

    bundle_rid = asc._find_bundle_id(token, WIDGET_BUNDLE)
    if not bundle_rid:
        print(f"ERRO: Bundle ID Widget nao encontrado: {WIDGET_BUNDLE}", file=sys.stderr)
        return 1
    print(f"Bundle Widget resource id: {bundle_rid}")
    ag.ensure_app_groups_on_bundle(bundle_rid, WIDGET_BUNDLE)

    cert_id = _resolve_distribution_cert_id(token)
    if cert_id:
        print(f"Cert Distribution id: {cert_id}")
        for pr in asc._profiles_for_bundle(token, bundle_rid):
            attr = pr.get("attributes") or {}
            if str(attr.get("profileType") or "") != "IOS_APP_STORE":
                continue
            pid = str(pr.get("id") or "")
            if not pid:
                continue
            if cert_id and not asc._profile_includes_certificate(token, pid, cert_id):
                continue
            raw = asc._download_profile_content(token, pid)
            if not raw:
                continue
            # Preferir com grupo; senao instalar na mesma.
            try:
                _install_widget_profile(raw)
                return 0
            except Exception as e:
                print(f"AVISO: instalar ASC {pid}: {e}", file=sys.stderr)

    if _fetch_signing_files_widget():
        return 0
    # fetch pode falhar por private key — tenta local sem exigir grupo
    if _try_install_local_matching(require_group=False):
        return 0

    if cert_id and _create_via_rest_once(token, bundle_rid, cert_id):
        return 0

    print(
        "ERRO: nao foi possivel obter/instalar nenhum perfil Widget.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception as e:
        print(f"ERRO: ensure widget profile: {e}", file=sys.stderr)
        raise SystemExit(1)
