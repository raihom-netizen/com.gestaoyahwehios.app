#!/usr/bin/env python3
"""
App Store Connect API: garante um perfil IOS_APP_STORE para o bundle que inclua o certificado
Apple Distribution cujo SHA256 coincide com o leaf do P12 em /tmp/cm_distribution.p12.

Usa JWT (PyJWT) + /tmp/_asc_ok.pem. Se criar perfil novo, grava o .mobileprovision e
/tmp/cm_prov.plist + /tmp/ExportOptions.plist + cópia em Provisioning Profiles.

Ambiente: APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_ISSUER_ID,
           CM_CERTIFICATE_PASSWORD (opcional), IOS_BUNDLE_ID (default com.gestaoyahwehios.app)

Saída: 0 se perfil alinhado (já existia ou foi criado); 1 se erro irrecuperável; 0 com aviso se saltar.
"""
from __future__ import annotations

import base64
import json
import os
import plistlib
import re
import tempfile
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def _fp_sha256_der(der: bytes) -> str:
    p = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-fingerprint", "-sha256"],
        input=der,
        capture_output=True,
    )
    if p.returncode != 0:
        return ""
    line = p.stdout.decode().strip()
    if "=" not in line:
        return ""
    return line.split("=", 1)[-1].replace(":", "").upper()


def _norm_serial(s: str) -> str:
    t = (s or "").replace(" ", "").replace(":", "").upper()
    if t.startswith("0X"):
        t = t[2:]
    return t


def _resolve_p12_password() -> str:
    p = os.environ.get("CM_CERTIFICATE_PASSWORD") or os.environ.get("CERTIFICATE_PASSWORD") or ""
    return (p or "").strip().replace("\n", "").replace("\r", "")


def _p12_leaf_der(path: str, password: str) -> bytes:
    password = (password or "").strip().replace("\n", "").replace("\r", "")
    pw_path = None
    try:
        if password:
            fd, pw_path = tempfile.mkstemp(prefix="cm_p12_pw_")
            with os.fdopen(fd, "wb") as f:
                f.write(password.encode("utf-8"))
            cmd = [
                "openssl",
                "pkcs12",
                "-in",
                path,
                "-passin",
                f"file:{pw_path}",
                "-clcerts",
                "-nokeys",
            ]
        else:
            cmd = ["openssl", "pkcs12", "-in", path, "-nodes", "-passin", "pass:", "-clcerts", "-nokeys"]
        p1 = subprocess.run(cmd, capture_output=True)
    finally:
        if pw_path:
            try:
                os.unlink(pw_path)
            except OSError:
                pass
    if p1.returncode != 0:
        raise RuntimeError("openssl pkcs12 falhou (senha CM_CERTIFICATE_PASSWORD?)")
    p2 = subprocess.run(
        ["openssl", "x509", "-outform", "DER"],
        input=p1.stdout,
        capture_output=True,
    )
    if p2.returncode != 0 or not p2.stdout:
        raise RuntimeError("PEM→DER do leaf falhou")
    return p2.stdout


def _ensure_jwt():
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--user", "-q", "pyjwt", "cryptography"],
        check=False,
    )
    import jwt  # type: ignore  # noqa: E402

    key_id = os.environ.get("APP_STORE_CONNECT_KEY_IDENTIFIER", "").strip()
    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
    pem_path = "/tmp/_asc_ok.pem"
    if not key_id or not issuer or not os.path.isfile(pem_path):
        raise RuntimeError("APP_STORE_CONNECT_KEY_IDENTIFIER / ISSUER_ID ou /tmp/_asc_ok.pem ausente")
    with open(pem_path, "r", encoding="utf-8") as f:
        key = f.read()
    now = int(time.time())
    token = jwt.encode(
        {
            "iss": issuer,
            "iat": now,
            "exp": now + 1100,
            "aud": "appstoreconnect-v1",
        },
        key,
        algorithm="ES256",
        headers={"kid": key_id, "alg": "ES256", "typ": "JWT"},
    )
    if isinstance(token, bytes):
        token = token.decode("ascii")
    return token


def _request(method: str, url: str, token: str, body: dict | None = None) -> tuple[int, dict]:
    data = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            return resp.getcode(), json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(err_body)
        except json.JSONDecodeError:
            parsed = {"errors": err_body}
        return e.code, parsed


def _find_bundle_id(token: str, bundle: str) -> str | None:
    q = urllib.parse.urlencode({"filter[identifier]": bundle, "limit": "5"})
    url = f"https://api.appstoreconnect.apple.com/v1/bundleIds?{q}"
    code, data = _request("GET", url, token)
    if code != 200:
        print(f"AVISO: GET bundleIds falhou {code}: {data}", file=sys.stderr)
        return None
    arr = data.get("data") or []
    if not arr:
        return None
    return str(arr[0].get("id") or "")


def _serial_hex_upper_from_der(der: bytes) -> str:
    p = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-serial"],
        input=der,
        capture_output=True,
    )
    if p.returncode != 0:
        return ""
    # serial=01:23:AB... ou serial=0xABCD...
    line = p.stdout.decode().strip()
    if "=" not in line:
        return ""
    raw = line.split("=", 1)[-1].strip().replace(":", "").upper()
    if raw.startswith("0X"):
        raw = raw[2:]
    return raw


def _certificates_paginated(token: str, query_suffix: str) -> list[dict]:
    """query_suffix ex.: '?filter[certificateType]=IOS_DISTRIBUTION&limit=200' ou '?limit=200'."""
    base = "https://api.appstoreconnect.apple.com/v1/certificates"
    url = base + (query_suffix if query_suffix.startswith("?") else "?" + query_suffix)
    rows: list[dict] = []
    while url:
        code, data = _request("GET", url, token)
        if code != 200:
            print(f"AVISO: GET certificates {url[:80]}... falhou {code}: {data}", file=sys.stderr)
            break
        for item in data.get("data") or []:
            cid = str(item.get("id") or "")
            attr = item.get("attributes") or {}
            b64 = attr.get("certificateContent")
            serial_api = _norm_serial(str(attr.get("serialNumber") or ""))
            if cid and not b64:
                c2, d2 = _request(
                    "GET",
                    f"https://api.appstoreconnect.apple.com/v1/certificates/{cid}",
                    token,
                )
                if c2 == 200:
                    attr2 = (d2.get("data") or {}).get("attributes") or {}
                    b64 = attr2.get("certificateContent") or b64
                    if not serial_api:
                        serial_api = _norm_serial(str(attr2.get("serialNumber") or ""))
            if not cid or not b64:
                continue
            try:
                der = base64.b64decode(b64)
            except Exception:
                continue
            fp = _fp_sha256_der(der)
            ser_local = _serial_hex_upper_from_der(der)
            if fp:
                rows.append(
                    {
                        "id": cid,
                        "der": der,
                        "fingerprint_sha256": fp,
                        "serial_local": ser_local,
                        "serial_api": serial_api,
                        "name": attr.get("displayName") or attr.get("name") or "",
                    }
                )
        next_url = (data.get("links") or {}).get("next")
        url = next_url if next_url else None
    return rows


def _list_distribution_certificates(token: str) -> list[dict]:
    """IOS_DISTRIBUTION primeiro; se não houver match pelo caller, usar listagem ampla."""
    seen: dict[str, dict] = {}
    for suffix in (
        "?filter[certificateType]=IOS_DISTRIBUTION&limit=200",
        "?limit=200",
    ):
        for row in _certificates_paginated(token, suffix):
            seen[row["id"]] = row
    return list(seen.values())


def _spki_der_from_pubkey(pub) -> bytes:
    from cryptography.hazmat.primitives import serialization

    return pub.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def _load_distribution_private_key_from_env():
    """PEM RSA/EC (ou Base64 do PEM) em CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM / CERTIFICATE_PRIVATE_KEY."""
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--user", "-q", "cryptography"],
        check=False,
    )
    from cryptography.hazmat.primitives import serialization

    def to_pem_bytes(raw: str) -> bytes | None:
        text = raw.strip()
        if re.search(r"BEGIN (EC |RSA |OPENSSH )?PRIVATE KEY", text):
            return text.encode("utf-8")
        b64 = "".join(text.split())
        try:
            decoded = base64.b64decode(b64, validate=False)
        except Exception:
            return None
        if re.search(rb"BEGIN (EC |RSA |OPENSSH )?PRIVATE KEY", decoded):
            return decoded
        return None

    for envname in ("CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM", "CERTIFICATE_PRIVATE_KEY"):
        raw = (os.environ.get(envname) or "").strip()
        if not raw:
            continue
        pem_bytes = to_pem_bytes(raw)
        if not pem_bytes:
            continue
        try:
            return serialization.load_pem_private_key(pem_bytes, password=None)
        except Exception:
            continue
    return None


def _find_cert_id_for_privkey(priv, certs: list[dict]) -> str | None:
    from cryptography import x509

    want = _spki_der_from_pubkey(priv.public_key())
    for c in certs:
        der = c.get("der")
        if not isinstance(der, (bytes, bytearray)) or not der:
            continue
        try:
            cert = x509.load_der_x509_certificate(bytes(der))
            got = _spki_der_from_pubkey(cert.public_key())
        except Exception:
            continue
        if got == want:
            return str(c.get("id") or "")
    return None


def download_app_store_profile_api_only_main() -> int:
    """
    Descarrega um perfil IOS_APP_STORE via REST (sem depender do CLI fetch-signing-files).
    Se existir CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (ou CERTIFICATE_PRIVATE_KEY em PEM),
    prefere perfis que incluam o certificado cujo par de chaves coincide com o PEM.
    """
    if os.environ.get("CM_SKIP_ASC_PROFILE_SYNC", "").strip() == "1":
        print("CM_SKIP_ASC_PROFILE_SYNC=1 — saltar download REST.")
        return 1
    bundle = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app").strip()
    try:
        token = _ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT: {e}", file=sys.stderr)
        return 1
    bundle_rid = _find_bundle_id(token, bundle)
    if not bundle_rid:
        print(f"ERRO: bundleId {bundle} não encontrado na App Store Connect.", file=sys.stderr)
        return 1
    priv = _load_distribution_private_key_from_env()
    cert_id: str | None = None
    certs = _list_distribution_certificates(token)
    if priv is not None:
        cert_id = _find_cert_id_for_privkey(priv, certs)
        if not cert_id:
            print(
                "AVISO: PEM local não corresponde a nenhum certificado IOS_DISTRIBUTION na API.",
                file=sys.stderr,
            )
    profiles = _profiles_for_bundle(token, bundle_rid)
    options: list[tuple[str, str, str]] = []
    for pr in profiles:
        attr = pr.get("attributes") or {}
        if str(attr.get("profileType") or "") != "IOS_APP_STORE":
            continue
        pid = str(pr.get("id") or "")
        if not pid:
            continue
        if cert_id and not _profile_includes_certificate(token, pid, cert_id):
            continue
        name = str(attr.get("name") or "")
        exp = str(attr.get("expirationDate") or "")
        options.append((exp, pid, name))
    options.sort(reverse=True)
    for _exp, pid, name in options:
        raw = _download_profile_content(token, pid)
        if raw:
            _write_mobileprovision_and_plist(raw, bundle)
            print(f"OK: perfil via REST ASC (nome={name!r}, id={pid}).")
            return 0
    if cert_id:
        unique = f"GestaoYahweh_CI_REST_{int(time.time())}"
        created = _create_app_store_profile(token, bundle_rid, cert_id, bundle, unique)
        if created:
            inline = created.get("_inline_profileContent")
            if isinstance(inline, str) and inline:
                try:
                    raw2 = base64.b64decode(inline)
                except Exception:
                    raw2 = b""
                if raw2:
                    _write_mobileprovision_and_plist(raw2, bundle)
                    print(f"OK: perfil IOS_APP_STORE criado via REST ({unique}).")
                    return 0
            new_id = str(created.get("id") or "")
            if new_id:
                raw = _download_profile_content(token, new_id)
                if raw:
                    _write_mobileprovision_and_plist(raw, bundle)
                    print(f"OK: perfil IOS_APP_STORE criado via REST (GET id={new_id}).")
                    return 0
    print("ERRO: nenhum perfil IOS_APP_STORE utilizável na API ASC (REST).", file=sys.stderr)
    return 1


def _find_cert_for_p12(fp_p12: str, der_p12: bytes, certs: list[dict]) -> dict | None:
    for c in certs:
        if c.get("fingerprint_sha256") == fp_p12:
            return c
    ser_p12 = _serial_hex_upper_from_der(der_p12)
    if not ser_p12:
        return None
    for c in certs:
        sa = _norm_serial(str(c.get("serial_api") or ""))
        sl = _norm_serial(str(c.get("serial_local") or ""))
        if ser_p12 and (ser_p12 == sa or ser_p12 == sl):
            return c
    return None


def _profiles_for_bundle(token: str, bundle_id_resource: str) -> list[dict]:
    out: list[dict] = []
    q = urllib.parse.urlencode({"filter[bundleId]": bundle_id_resource, "limit": "50"})
    url = f"https://api.appstoreconnect.apple.com/v1/profiles?{q}"
    code_last, data_last = 0, {}
    while url:
        code, data = _request("GET", url, token)
        code_last, data_last = code, data
        if code != 200:
            print(f"AVISO: GET profiles {url[:90]}... falhou {code}: {data}", file=sys.stderr)
            break
        out.extend(list(data.get("data") or []))
        next_url = (data.get("links") or {}).get("next")
        url = next_url if next_url else None
    # include=profiles no bundleId (perfis ligados ao App ID).
    url_inc = f"https://api.appstoreconnect.apple.com/v1/bundleIds/{bundle_id_resource}?include=profiles"
    code2, data2 = _request("GET", url_inc, token)
    if code2 == 200:
        for item in data2.get("included") or []:
            if item.get("type") == "profiles":
                out.append(item)
    if not out and code_last != 200:
        print(f"AVISO: GET profiles falhou {code_last}: {data_last}", file=sys.stderr)
    by_id = {str(x.get("id")): x for x in out if x.get("id")}
    return list(by_id.values())


def _profile_includes_certificate(token: str, profile_id: str, cert_id: str) -> bool:
    url = f"https://api.appstoreconnect.apple.com/v1/profiles/{profile_id}/relationships/certificates?limit=50"
    code, data = _request("GET", url, token)
    if code != 200:
        return False
    for item in data.get("data") or []:
        if str(item.get("id")) == cert_id:
            return True
    return False


def _download_profile_content(token: str, profile_id: str) -> bytes | None:
    url = f"https://api.appstoreconnect.apple.com/v1/profiles/{profile_id}"
    code, data = _request("GET", url, token)
    if code != 200:
        return None
    attr = (data.get("data") or {}).get("attributes") or {}
    b64 = attr.get("profileContent")
    if not b64:
        return None
    try:
        return base64.b64decode(b64)
    except Exception:
        return None


def _create_app_store_profile(
    token: str, bundle_rid: str, cert_id: str, bundle: str, unique_name: str
) -> dict | None:
    body = {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": unique_name,
                "profileType": "IOS_APP_STORE",
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_rid}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    }
    code, data = _request("POST", "https://api.appstoreconnect.apple.com/v1/profiles", token, body)
    if code in (200, 201):
        row = data.get("data") or {}
        attr = row.get("attributes") or {}
        b64 = attr.get("profileContent")
        if b64:
            row["_inline_profileContent"] = b64
        return row
    print(f"AVISO: POST profiles falhou {code}: {json.dumps(data)[:2000]}", file=sys.stderr)
    return None


def _write_mobileprovision_and_plist(mp_bytes: bytes, bundle: str) -> None:
    prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(prov_dir, exist_ok=True)
    with open("/tmp/cm_raw.mobileprovision", "wb") as f:
        f.write(mp_bytes)
    with open("/tmp/cm_prov.plist", "wb") as out_plist:
        subprocess.run(
            ["security", "cms", "-D", "-i", "/tmp/cm_raw.mobileprovision"],
            stdout=out_plist,
            check=True,
        )
    with open("/tmp/cm_prov.plist", "rb") as f:
        pl = plistlib.load(f)
    uuid = str(pl.get("UUID") or "")
    name = str(pl.get("Name") or "")
    team = ""
    tid = pl.get("TeamIdentifier")
    if isinstance(tid, list) and tid:
        team = str(tid[0])
    elif isinstance(tid, str):
        team = tid
    if uuid:
        shutil.copyfile("/tmp/cm_raw.mobileprovision", os.path.join(prov_dir, f"{uuid}.mobileprovision"))
    exp = {
        "method": "app-store",
        "signingStyle": "manual",
        "teamID": team,
        "uploadSymbols": True,
        "provisioningProfiles": {bundle: name},
    }
    with open("/tmp/ExportOptions.plist", "wb") as f:
        plistlib.dump(exp, f, fmt=plistlib.FMT_XML)
    print(f"OK: perfil escrito (API). name={name} uuid={uuid} team={team}")


def import_distribution_identity_to_keychain_main() -> int:
    """
    PEM (CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM ou CERTIFICATE_PRIVATE_KEY) + leaf DER na ASC
    → PKCS#12 temporário → keychain add-certificates (Codemagic).
    Necessário para exportArchive quando só há .mobileprovision (REST/CLI) sem P12 nos secrets.
    """
    priv = _load_distribution_private_key_from_env()
    if priv is None:
        print(
            "ERRO: PEM de chave privada não encontrada (CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM ou CERTIFICATE_PRIVATE_KEY PEM).",
            file=sys.stderr,
        )
        return 1
    try:
        token = _ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT: {e}", file=sys.stderr)
        return 1
    certs = _list_distribution_certificates(token)
    cert_id = _find_cert_id_for_privkey(priv, certs)
    if not cert_id:
        print(
            "ERRO: o PEM não corresponde a nenhum certificado IOS_DISTRIBUTION desta equipa na App Store Connect.",
            file=sys.stderr,
        )
        return 1
    der: bytes | None = None
    for c in certs:
        if str(c.get("id") or "") == cert_id:
            d = c.get("der")
            if isinstance(d, (bytes, bytearray)):
                der = bytes(d)
            break
    if not der:
        print("ERRO: certificado na API sem DER.", file=sys.stderr)
        return 1
    from cryptography.hazmat.primitives import serialization

    key_pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    paths = (
        "/tmp/cm_api_only_priv.pem",
        "/tmp/cm_api_only_leaf.der",
        "/tmp/cm_api_only_leaf.pem",
        "/tmp/cm_api_only_identity.p12",
    )
    for path in paths:
        try:
            if os.path.isfile(path):
                os.unlink(path)
        except OSError:
            pass
    with open("/tmp/cm_api_only_priv.pem", "wb") as f:
        f.write(key_pem)
    with open("/tmp/cm_api_only_leaf.der", "wb") as f:
        f.write(der)
    os.chmod("/tmp/cm_api_only_priv.pem", 0o600)
    os.chmod("/tmp/cm_api_only_leaf.der", 0o600)
    p1 = subprocess.run(
        [
            "openssl",
            "x509",
            "-inform",
            "DER",
            "-in",
            "/tmp/cm_api_only_leaf.der",
            "-out",
            "/tmp/cm_api_only_leaf.pem",
        ],
        capture_output=True,
        text=True,
    )
    if p1.returncode != 0:
        print(p1.stderr or p1.stdout, file=sys.stderr)
        return 1
    os.chmod("/tmp/cm_api_only_leaf.pem", 0o600)
    pw = (os.environ.get("CM_API_ONLY_IMPORT_P12_PASSWORD") or "cm_yw_dist_import_1").strip() or "cm_yw_dist_import_1"

    def run_pkcs12(extra: list[str]) -> subprocess.CompletedProcess:
        cmd: list[str] = [
            "openssl",
            "pkcs12",
            "-export",
            "-out",
            "/tmp/cm_api_only_identity.p12",
            "-inkey",
            "/tmp/cm_api_only_priv.pem",
            "-in",
            "/tmp/cm_api_only_leaf.pem",
            "-passout",
            f"pass:{pw}",
            "-name",
            "Apple Distribution",
        ]
        cmd[2:2] = extra  # insert after "pkcs12"
        return subprocess.run(cmd, capture_output=True, text=True)

    p2 = run_pkcs12([])
    if p2.returncode != 0:
        p2 = run_pkcs12(["-legacy"])
    if p2.returncode != 0:
        print(p2.stderr or p2.stdout, file=sys.stderr)
        return 1
    os.chmod("/tmp/cm_api_only_identity.p12", 0o600)
    kc = shutil.which("keychain")
    if not kc:
        print(
            "ERRO: comando «keychain» não encontrado (use o passo «keychain initialize» antes deste script).",
            file=sys.stderr,
        )
        return 1
    p3 = subprocess.run(
        [kc, "add-certificates", "--certificate", "/tmp/cm_api_only_identity.p12", "--certificate-password", pw],
        capture_output=True,
        text=True,
    )
    if p3.returncode != 0:
        msg = (p3.stderr or p3.stdout or "").strip()
        print(f"ERRO: keychain add-certificates: {msg}", file=sys.stderr)
        return 1
    print("OK: identidade Apple Distribution importada (PEM + certificado ASC).")
    return 0


def bootstrap_distribution_cert_ci_main() -> int:
    """
    Sem Mac: gera RSA+CSR na CI, POST IOS_DISTRIBUTION na ASC, importa no keychain,
    cria/usa perfil IOS_APP_STORE para IOS_BUNDLE_ID e grava PEM em bootstrap_signing_output/
    (artefacto Codemagic). Chave API com papel Admin.

    Uso: uma vez (ou com CM_CI_BOOTSTRAP_DISTRIBUTION_IF_NO_PEM=1 no mesmo build que o IPA);
    depois copie distribution_private_key.pem para o secret CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM
    e desligue o bootstrap para não criar mais certificados (limite 3 Distribution).
    """
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "--user", "-q", "cryptography"],
        check=False,
    )
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    if not os.path.isfile("/tmp/_asc_ok.pem"):
        print("ERRO: /tmp/_asc_ok.pem ausente (corra Preparar PEM App Store Connect antes).", file=sys.stderr)
        return 1
    try:
        token = _ensure_jwt()
    except Exception as e:
        print(f"ERRO: JWT: {e}", file=sys.stderr)
        return 1

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COUNTRY_NAME, "PT"),
                    x509.NameAttribute(NameOID.ORGANIZATION_NAME, "GestaoYAHWEH"),
                    x509.NameAttribute(NameOID.COMMON_NAME, "Gestao YAHWEH Codemagic Bootstrap"),
                ]
            )
        )
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode("ascii")
    csr_der = csr.public_bytes(serialization.Encoding.DER)
    csr_b64 = base64.b64encode(csr_der).decode("ascii")

    data_ok: dict | None = None
    used_label = ""
    for csr_content, label in ((csr_pem, "PEM"), (csr_b64, "base64-DER")):
        body = {
            "data": {
                "type": "certificates",
                "attributes": {
                    "certificateType": "IOS_DISTRIBUTION",
                    "csrContent": csr_content,
                },
            }
        }
        code, data = _request("POST", "https://api.appstoreconnect.apple.com/v1/certificates", token, body)
        if code in (200, 201):
            data_ok = data
            used_label = label
            print(f"OK: POST certificates (CSR como {label}).")
            break
        print(f"AVISO: POST certificates com CSR {label} falhou {code}: {json.dumps(data)[:1200]}", file=sys.stderr)
    if not data_ok:
        print(
            "ERRO: não foi possível criar IOS_DISTRIBUTION (403/409?). Revogue um Distribution antigo se exceder 3.",
            file=sys.stderr,
        )
        return 1

    row = data_ok.get("data") or {}
    cert_id = str(row.get("id") or "")
    attr = row.get("attributes") or {}
    b64cert = attr.get("certificateContent")
    if not cert_id or not b64cert:
        print("ERRO: resposta sem id/certificateContent.", file=sys.stderr)
        return 1
    try:
        cert_der = base64.b64decode(b64cert)
    except Exception as e:
        print(f"ERRO: decode certificateContent: {e}", file=sys.stderr)
        return 1

    root = (os.environ.get("CM_BUILD_DIR") or os.environ.get("FCI_BUILD_DIR") or os.getcwd()).strip()
    out_dir = (os.environ.get("CM_BOOTSTRAP_SIGNING_OUT_DIR") or "").strip() or os.path.join(root, "bootstrap_signing_output")
    os.makedirs(out_dir, exist_ok=True)
    key_path = os.path.join(out_dir, "distribution_private_key.pem")
    cer_path = os.path.join(out_dir, "distribution_leaf.der")
    key_pem_bytes = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    with open(key_path, "wb") as f:
        f.write(key_pem_bytes)
    with open(cer_path, "wb") as f:
        f.write(cert_der)
    os.chmod(key_path, 0o600)
    os.chmod(cer_path, 0o600)

    leaf_pem = os.path.join(out_dir, "distribution_leaf.pem")
    p1 = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-in", cer_path, "-out", leaf_pem],
        capture_output=True,
        text=True,
    )
    if p1.returncode != 0:
        print(p1.stderr or p1.stdout, file=sys.stderr)
        return 1
    os.chmod(leaf_pem, 0o600)
    pw = (os.environ.get("CM_API_ONLY_IMPORT_P12_PASSWORD") or "cm_yw_bootstrap_dist_1").strip() or "cm_yw_bootstrap_dist_1"
    p12_path = os.path.join(out_dir, "bootstrap_identity.p12")

    def run_pkcs12(extra: list[str]) -> subprocess.CompletedProcess:
        cmd: list[str] = [
            "openssl",
            "pkcs12",
            "-export",
            "-out",
            p12_path,
            "-inkey",
            key_path,
            "-in",
            leaf_pem,
            "-passout",
            f"pass:{pw}",
            "-name",
            "Apple Distribution",
        ]
        cmd[2:2] = extra
        return subprocess.run(cmd, capture_output=True, text=True)

    p2 = run_pkcs12([])
    if p2.returncode != 0:
        p2 = run_pkcs12(["-legacy"])
    if p2.returncode != 0:
        print(p2.stderr or p2.stdout, file=sys.stderr)
        return 1
    os.chmod(p12_path, 0o600)
    kc = shutil.which("keychain")
    if not kc:
        print("ERRO: comando keychain ausente.", file=sys.stderr)
        return 1
    p3 = subprocess.run(
        [kc, "add-certificates", "--certificate", p12_path, "--certificate-password", pw],
        capture_output=True,
        text=True,
    )
    if p3.returncode != 0:
        print((p3.stderr or p3.stdout or "").strip(), file=sys.stderr)
        return 1

    bundle = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app").strip()
    bundle_rid = _find_bundle_id(token, bundle)
    if not bundle_rid:
        print(f"ERRO: bundleId {bundle} não encontrado na ASC.", file=sys.stderr)
        return 1

    raw_mp: bytes | None = None
    profiles = _profiles_for_bundle(token, bundle_rid)
    for pr in profiles:
        attr = pr.get("attributes") or {}
        if str(attr.get("profileType") or "") != "IOS_APP_STORE":
            continue
        pid = str(pr.get("id") or "")
        if not pid:
            continue
        if not _profile_includes_certificate(token, pid, cert_id):
            continue
        raw_mp = _download_profile_content(token, pid)
        if raw_mp:
            print(f"OK: reutilizar perfil IOS_APP_STORE existente (id={pid}).")
            break
    if not raw_mp:
        unique = f"GestaoYahwehBootstrap_{int(time.time())}"
        created = _create_app_store_profile(token, bundle_rid, cert_id, bundle, unique)
        if not created:
            print("ERRO: não foi possível criar perfil IOS_APP_STORE para o novo certificado.", file=sys.stderr)
            return 1
        inline = created.get("_inline_profileContent")
        if isinstance(inline, str) and inline:
            try:
                raw_mp = base64.b64decode(inline)
            except Exception:
                raw_mp = None
        if not raw_mp:
            new_id = str(created.get("id") or "")
            if new_id:
                raw_mp = _download_profile_content(token, new_id)
        if not raw_mp:
            print("ERRO: perfil criado mas sem profileContent.", file=sys.stderr)
            return 1
        print(f"OK: perfil IOS_APP_STORE criado ({unique}).")

    _write_mobileprovision_and_plist(raw_mp, bundle)

    with open(os.path.join(out_dir, "README_BOOTSTRAP.txt"), "w", encoding="utf-8") as f:
        f.write(
            "1) Codemagic: descarregue distribution_private_key.pem deste artefacto.\n"
            "2) Environment variables (appstore_credentials): CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM = "
            "conteudo COMPLETO do PEM (Secret, multilinha).\n"
            "3) Desligue CM_CI_BOOTSTRAP_DISTRIBUTION_IF_NO_PEM ou nao use o workflow ios-distribution-bootstrap "
            "para nao criar mais certificados Distribution (maximo 3 na equipa).\n"
            f"4) CSR enviado como: {used_label}\n"
        )

    print("")
    print("OK: bootstrap CI concluido — PEM em:", key_path)
    print("    Copie o ficheiro para o secret CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM e desligue o bootstrap.")
    return 0


def _local_tmp_profile_matches_p12(fp_p12: str) -> bool:
    plist_path = "/tmp/cm_prov.plist"
    if not os.path.isfile(plist_path):
        return False
    try:
        with open(plist_path, "rb") as f:
            pl = plistlib.load(f)
    except Exception:
        return False
    for item in pl.get("DeveloperCertificates") or []:
        if isinstance(item, (bytes, bytearray)):
            if _fp_sha256_der(bytes(item)) == fp_p12:
                return True
    return False


def matches_only_main() -> int:
    """Exit 0 se /tmp/cm_prov.plist inclui o leaf do P12 (SHA256); senão 1. Sem chamadas à API."""
    p12 = "/tmp/cm_distribution.p12"
    plist_path = "/tmp/cm_prov.plist"
    if not os.path.isfile(p12) or not os.path.isfile(plist_path):
        return 1
    pw = _resolve_p12_password()
    try:
        der = _p12_leaf_der(p12, pw)
        fp_p12 = _fp_sha256_der(der)
    except Exception:
        return 1
    if not fp_p12:
        return 1
    if _local_tmp_profile_matches_p12(fp_p12):
        print("OK: perfil e P12 coincidem (SHA256).")
        return 0
    return 1


def main() -> int:
    if "--matches-only" in sys.argv:
        return matches_only_main()
    if "--import-distribution-identity-to-keychain" in sys.argv:
        try:
            return import_distribution_identity_to_keychain_main()
        except Exception as e:
            print(f"ERRO: import identidade keychain: {e}", file=sys.stderr)
            return 1
    if "--bootstrap-distribution-cert-ci" in sys.argv:
        try:
            return bootstrap_distribution_cert_ci_main()
        except Exception as e:
            print(f"ERRO: bootstrap Distribution CI: {e}", file=sys.stderr)
            return 1
    if "--download-app-store-profile-api-only" in sys.argv:
        try:
            return download_app_store_profile_api_only_main()
        except Exception as e:
            print(f"ERRO: download REST perfil: {e}", file=sys.stderr)
            return 1
    if os.environ.get("CM_SKIP_ASC_PROFILE_SYNC", "").strip() == "1":
        print("CM_SKIP_ASC_PROFILE_SYNC=1 — saltar API de perfil.")
        return 0
    bundle = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app").strip()
    p12 = "/tmp/cm_distribution.p12"
    if not os.path.isfile(p12):
        print("AVISO: /tmp/cm_distribution.p12 ausente — saltar API profile.")
        return 0
    pw = _resolve_p12_password()
    try:
        der = _p12_leaf_der(p12, pw)
        fp_p12 = _fp_sha256_der(der)
    except Exception as e:
        print(f"AVISO: leitura P12: {e}", file=sys.stderr)
        return 0
    if not fp_p12:
        return 0

    if _local_tmp_profile_matches_p12(fp_p12):
        print("OK: /tmp/cm_prov.plist já inclui o certificado do P12 — saltar API.")
        return 0

    try:
        token = _ensure_jwt()
    except Exception as e:
        print(f"AVISO: JWT: {e}", file=sys.stderr)
        return 0

    certs = _list_distribution_certificates(token)
    match = _find_cert_for_p12(fp_p12, der, certs)
    if not match:
        print(
            "ERRO API: nenhum certificado na App Store Connect API corresponde ao P12 (SHA256 nem serial).",
            file=sys.stderr,
        )
        print(
            "         Confirme que CM_CERTIFICATE é o .p12 do certificado «Apple Distribution» desta equipa.",
            file=sys.stderr,
        )
        print(f"         P12 SHA256: {fp_p12}  |  certificados analisados na API: {len(certs)}", file=sys.stderr)
        return 0

    cert_id = match["id"]
    bundle_rid = _find_bundle_id(token, bundle)
    if not bundle_rid:
        print(f"AVISO: bundleId {bundle} não encontrado na API.", file=sys.stderr)
        return 0

    profiles = _profiles_for_bundle(token, bundle_rid)
    for pr in profiles:
        pid = str(pr.get("id") or "")
        attr = pr.get("attributes") or {}
        ptype = str(attr.get("profileType") or "")
        if ptype != "IOS_APP_STORE":
            continue
        if _profile_includes_certificate(token, pid, cert_id):
            raw = _download_profile_content(token, pid)
            if raw:
                _write_mobileprovision_and_plist(raw, bundle)
                print("OK: perfil App Store existente na API já inclui o certificado do P12.")
                return 0

    unique = f"GestaoYahweh_CI_{int(time.time())}"
    created = _create_app_store_profile(token, bundle_rid, cert_id, bundle, unique)
    if not created:
        return 0
    inline = created.get("_inline_profileContent")
    if inline:
        try:
            raw = base64.b64decode(inline)
            _write_mobileprovision_and_plist(raw, bundle)
            print(f"OK: novo perfil App Store criado via API (nome {unique}).")
            return 0
        except Exception as e:
            print(f"AVISO: decode profileContent POST: {e}", file=sys.stderr)
    new_id = str(created.get("id") or "")
    if not new_id:
        return 0
    raw = _download_profile_content(token, new_id)
    if not raw:
        print("AVISO: perfil criado mas profileContent não veio no GET — tente fetch-signing-files.", file=sys.stderr)
        return 0
    _write_mobileprovision_and_plist(raw, bundle)
    print(f"OK: novo perfil App Store criado via API (nome {unique}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print(f"AVISO: codemagic_ios_asc_api_ensure_appstore_profile: {e}", file=sys.stderr)
        sys.exit(0)
