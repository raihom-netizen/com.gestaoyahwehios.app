#!/usr/bin/env python3
"""
Ativa Sign In with Apple no App ID via App Store Connect API (mesmo padrão Controle Total App).
Requer: /tmp/_asc_ok.pem, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_IDENTIFIER,
variável opcional IOS_BUNDLE_ID (default com.gestaoyahwehios.app).
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


def _pip_install() -> None:
    subprocess.check_call(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--user",
            "-q",
            "PyJWT",
            "cryptography",
        ]
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


def _main_impl() -> int:
    if not ISSUER or not KEY_ID:
        print("AVISO: APP_STORE_CONNECT_ISSUER_ID ou KEY_IDENTIFIER vazio — a saltar Sign In with Apple API.")
        return 0
    if not os.path.isfile(PEM_PATH):
        print(f"ERRO: {PEM_PATH} ausente — execute Preparar PEM antes.")
        return 1

    print("A instalar PyJWT/cryptography (CI)...")
    _pip_install()

    token = _jwt_token()
    if isinstance(token, bytes):
        token = token.decode("utf-8")

    base = "https://api.appstoreconnect.apple.com/v1"
    url = f"{base}/bundleIds?filter%5Bidentifier%5D={quote(BUNDLE_FILTER, safe='')}"

    code, bundle_resp = _request("GET", url, token)
    if code != 200:
        print(f"AVISO: GET bundleIds HTTP {code}: {bundle_resp}")
        return 0

    data = bundle_resp.get("data") or []
    if not data:
        print(f"AVISO: nenhum Bundle ID '{BUNDLE_FILTER}' no App Store Connect (equipa/API).")
        return 0

    bid = data[0].get("id")
    if not bid:
        print("AVISO: resposta bundleIds sem id.")
        return 0

    detail_url = f"{base}/bundleIds/{bid}?include=bundleIdCapabilities"
    code2, detail = _request("GET", detail_url, token)
    if code2 == 200:
        for item in detail.get("included") or []:
            if item.get("type") != "bundleIdCapabilities":
                continue
            attr = item.get("attributes") or {}
            if attr.get("capabilityType") == "SIGN_IN_WITH_APPLE":
                print("OK: Sign In with Apple já está ativo no App ID.")
                return 0

    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {"capabilityType": "SIGN_IN_WITH_APPLE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bid}}
            },
        }
    }
    code3, post_resp = _request("POST", f"{base}/bundleIdCapabilities", token, body)
    if code3 in (200, 201):
        print("OK: Sign In with Apple ativado via API.")
        return 0
    if code3 == 409:
        print("OK: capability já existia (409).")
        return 0
    print(f"AVISO: POST bundleIdCapabilities HTTP {code3}: {post_resp}")
    print("Dica: ative manualmente em developer.apple.com → Identifiers → App ID → Sign In with Apple.")
    return 0


def main() -> int:
    try:
        return _main_impl()
    except (urllib.error.URLError, OSError, ValueError, RuntimeError, ImportError) as e:
        print(f"AVISO: Sign In with Apple (API) não concluído: {e}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
