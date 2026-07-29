#!/usr/bin/env python3
"""
Ativa Associated Domains (ASSOCIATED_DOMAINS) no App ID via App Store Connect API.
Sem esta capability, o perfil App Store nao inclui o entitlement
com.apple.developer.associated-domains e o Xcode falha:
  "Provisioning profile ... doesn't include the Associated Domains capability."
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Optional
from urllib.parse import quote

BUNDLE_FILTER = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app").strip()
ISSUER = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "").strip()
KEY_ID = os.environ.get("APP_STORE_CONNECT_KEY_IDENTIFIER", "").strip()
PEM_PATH = "/tmp/_asc_ok.pem"
CAP = "ASSOCIATED_DOMAINS"


def _pip_install() -> None:
    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "--user", "-q", "PyJWT", "cryptography"]
    )


def _jwt_token() -> str:
    import jwt  # type: ignore

    with open(PEM_PATH, "rb") as f:
        key = f.read()
    now = int(time.time())
    payload = {
        "iss": ISSUER,
        "iat": now,
        "exp": now + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})


def _request(
    method: str, url: str, token: str, body: Optional[dict] = None
) -> tuple[int, dict]:
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
            raw = resp.read().decode("utf-8", errors="replace")
            return resp.status, json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(err_body) if err_body.strip() else {}
        except json.JSONDecodeError:
            parsed = {"raw": err_body}
        return e.code, parsed


def _exact_bundle_id(token: str, base: str) -> Optional[str]:
    """Match exato — evita retornar o Widget antes do app principal."""
    url = f"{base}/bundleIds?filter%5Bidentifier%5D={quote(BUNDLE_FILTER, safe='')}&limit=50"
    code, bundle_resp = _request("GET", url, token)
    if code != 200:
        print(f"AVISO: GET bundleIds HTTP {code}: {bundle_resp}")
        return None
    for item in bundle_resp.get("data") or []:
        attrs = (item or {}).get("attributes") or {}
        if str(attrs.get("identifier") or "") == BUNDLE_FILTER:
            rid = item.get("id")
            return str(rid) if rid else None
    data = bundle_resp.get("data") or []
    if data:
        print(
            f"AVISO: match exato falhou; a usar primeiro resultado "
            f"{(data[0].get('attributes') or {}).get('identifier')}"
        )
        return data[0].get("id")
    return None


def _main_impl() -> int:
    if not ISSUER or not KEY_ID:
        print("AVISO: APP_STORE_CONNECT_ISSUER_ID ou KEY_IDENTIFIER vazio — a saltar Associated Domains API.")
        return 0
    if not os.path.isfile(PEM_PATH):
        print(f"ERRO: {PEM_PATH} ausente — execute 'Preparar PEM' antes.")
        return 1

    print("A instalar PyJWT/cryptography (CI)...")
    _pip_install()

    token = _jwt_token()
    if isinstance(token, bytes):
        token = token.decode("utf-8")

    base = "https://api.appstoreconnect.apple.com/v1"
    bid = _exact_bundle_id(token, base)
    if not bid:
        print(f"AVISO: nenhum Bundle ID '{BUNDLE_FILTER}' no App Store Connect.")
        return 0

    detail_url = f"{base}/bundleIds/{bid}?include=bundleIdCapabilities"
    code2, detail = _request("GET", detail_url, token)
    if code2 == 200:
        for item in detail.get("included") or []:
            if item.get("type") != "bundleIdCapabilities":
                continue
            attr = item.get("attributes") or {}
            if attr.get("capabilityType") == CAP:
                print(f"OK: {CAP} ja esta ativo no App ID {BUNDLE_FILTER}.")
                return 0

    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": CAP},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bid}}
            },
        }
    }
    code3, post_resp = _request("POST", f"{base}/bundleIdCapabilities", token, body)
    if code3 in (200, 201):
        print(f"OK: {CAP} ativado via API no App ID {BUNDLE_FILTER}.")
        return 0
    if code3 == 409:
        print(f"OK: capability {CAP} ja existia (409).")
        return 0
    print(f"AVISO: POST bundleIdCapabilities HTTP {code3}: {post_resp}")
    print(
        f"Dica: ative Associated Domains em developer.apple.com -> Identifiers -> "
        f"{BUNDLE_FILTER} -> Associated Domains."
    )
    return 0


def main() -> int:
    try:
        return _main_impl()
    except (urllib.error.URLError, OSError, ValueError, RuntimeError, ImportError) as e:
        print(f"AVISO: Associated Domains (API) nao concluido: {e}")
        return 0


if __name__ == "__main__":
    sys.exit(main())