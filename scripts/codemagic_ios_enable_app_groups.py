"""
Registra App Group, associa ao App ID principal e ao Widget.
Usa REST API (chave .p8 do Codemagic) + fallback CLI app-store-connect.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_asc_api import api_request  # noqa: E402

APP_GROUP = os.environ.get("APP_GROUP_ID", "group.com.gestaoyahwehios.app.widget")
APP_GROUP_NAME = os.environ.get("APP_GROUP_NAME", "Gestao Yahweh Widget")
BUNDLES = [
    os.environ.get("BUNDLE_ID", "com.gestaoyahwehios.app"),
    os.environ.get("WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget"),
]
CAP_CANDIDATES = ("App Groups", "APP_GROUPS")


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True)


def _bundle_resource_id(identifier: str) -> str | None:
    r = _run(
        [
            "app-store-connect",
            "bundle-ids",
            "list",
            "--bundle-id-identifier",
            identifier,
            "--strict-match-identifier",
            "--platform",
            "IOS",
            "--json",
            "-s",
        ]
    )
    if r.returncode != 0:
        print("ERRO bundle-ids list:", identifier, (r.stderr or r.stdout)[:600])
        return None
    try:
        j = json.loads((r.stdout or "").strip() or "null")
    except json.JSONDecodeError as e:
        print("ERRO JSON bundle-ids list:", e)
        return None
    data = j.get("data") if isinstance(j, dict) else (j if isinstance(j, list) else [])
    if not data or not isinstance(data[0], dict):
        print("AVISO: Bundle ID não encontrado:", identifier, "— tentando criar via API...")
        return _create_bundle_id_api(identifier)
    rid = data[0].get("id")
    print("Bundle ID", identifier, "→ resource id", rid)
    return rid


def _create_bundle_id_api(identifier: str) -> str | None:
    """Cria App ID iOS (necessário para a extensão Widget no primeiro build)."""
    name = identifier.replace(".", " ")[-50:]
    if identifier.endswith("GestaoYahwehWidget"):
        name = "Gestao Yahweh Widget"
    body = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        }
    }
    try:
        created = api_request("POST", "/bundleIds", body=body, ok_status=(200, 201))
        rid = (created or {}).get("data", {}).get("id")
        print(f"Bundle ID criado: {identifier} (id={rid})")
        return rid
    except RuntimeError as e:
        low = str(e).lower()
        if any(x in low for x in ("already", "duplicate", "409", "exists", "not unique")):
            print(f"Bundle ID {identifier} já existe — relendo...")
            r = _run(
                [
                    "app-store-connect",
                    "bundle-ids",
                    "list",
                    "--bundle-id-identifier",
                    identifier,
                    "--strict-match-identifier",
                    "--platform",
                    "IOS",
                    "--json",
                    "-s",
                ]
            )
            try:
                j = json.loads((r.stdout or "").strip() or "null")
                data = j.get("data") if isinstance(j, dict) else (j if isinstance(j, list) else [])
                if data and isinstance(data[0], dict):
                    return data[0].get("id")
            except Exception:
                pass
        print("ERRO criar Bundle ID:", identifier, str(e)[:500])
        return None


def _app_group_settings() -> list[dict]:
    return [
        {
            "key": "APP_GROUP_IDS",
            "options": [{"key": APP_GROUP, "enabled": True}],
        }
    ]


def _ensure_app_group_registered_api() -> bool:
    try:
        listed = api_request(
            "GET",
            f"/appGroups?filter[identifier]={APP_GROUP}&limit=1",
        )
        data = (listed or {}).get("data") or []
        if data:
            print(f"OK: App Group já registrado: {APP_GROUP} (id={data[0].get('id')})")
            return True
    except RuntimeError as e:
        print("AVISO list appGroups:", str(e)[:400])

    body = {
        "data": {
            "type": "appGroups",
            "attributes": {
                "identifier": APP_GROUP,
                "name": APP_GROUP_NAME,
            },
        }
    }
    try:
        created = api_request("POST", "/appGroups", body=body, ok_status=(200, 201))
        gid = (created or {}).get("data", {}).get("id")
        print(f"App Group criado: {APP_GROUP} (id={gid})")
        return True
    except RuntimeError as e:
        low = str(e).lower()
        if any(x in low for x in ("already", "duplicate", "409", "exists", "not unique")):
            print(f"App Group {APP_GROUP} já existe (API).")
            return True
        print("ERRO POST appGroups:", str(e)[:600])
        return False


def _list_bundle_capabilities(bundle_rid: str) -> list[dict]:
    r = _run(
        [
            "app-store-connect",
            "bundle-ids",
            "capabilities",
            bundle_rid,
            "--json",
            "-s",
        ]
    )
    if r.returncode != 0:
        print("ERRO capabilities list:", (r.stderr or r.stdout)[:600])
        return []
    try:
        j = json.loads((r.stdout or "").strip() or "null")
    except json.JSONDecodeError:
        return []
    if isinstance(j, dict):
        return j.get("data") or []
    if isinstance(j, list):
        return j
    return []


def _capability_blob(bundle_rid: str) -> str:
    return json.dumps(_list_bundle_capabilities(bundle_rid))


def _has_app_groups_capability(blob: str) -> bool:
    return bool(re.search(r"APP_GROUPS|App Groups", blob, re.I))


def _has_app_groups_with_target(bundle_rid: str) -> bool:
    blob = _capability_blob(bundle_rid)
    if not _has_app_groups_capability(blob):
        return False
    return APP_GROUP in blob


def _find_app_groups_capability_id(bundle_rid: str) -> str | None:
    for cap in _list_bundle_capabilities(bundle_rid):
        attrs = cap.get("attributes") or {}
        ctype = str(attrs.get("capabilityType") or attrs.get("capability_type") or "")
        if ctype.upper() == "APP_GROUPS" or "app groups" in ctype.lower():
            return cap.get("id")
    return None


def _patch_app_groups_capability(cap_id: str) -> bool:
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "id": cap_id,
            "attributes": {
                "settings": _app_group_settings(),
            },
        }
    }
    try:
        api_request("PATCH", f"/bundleIdCapabilities/{cap_id}", body=body)
        print(f"PATCH bundleIdCapabilities/{cap_id} com grupo {APP_GROUP}")
        return True
    except RuntimeError as e:
        print(f"AVISO PATCH capability: {str(e)[:500]}")
        return False


def _create_app_groups_capability_api(bundle_rid: str) -> bool:
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "APP_GROUPS",
                "settings": _app_group_settings(),
            },
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle_rid},
                }
            },
        }
    }
    try:
        api_request("POST", "/bundleIdCapabilities", body=body, ok_status=(200, 201))
        print(f"POST APP_GROUPS + {APP_GROUP} em bundle {bundle_rid}")
        return True
    except RuntimeError as e:
        low = str(e).lower()
        if any(x in low for x in ("already", "duplicate", "409", "exists")):
            return True
        print(f"ERRO POST capability: {str(e)[:500]}")
        return False


def _enable_via_cli(bundle_rid: str, identifier: str) -> bool:
    last_out = ""
    for cap in CAP_CANDIDATES:
        ec = _run(
            [
                "app-store-connect",
                "bundle-ids",
                "enable-capabilities",
                bundle_rid,
                "--capability",
                cap,
            ]
        )
        out = ((ec.stderr or "") + (ec.stdout or "")).strip()
        last_out = out
        low = out.lower()
        if ec.returncode == 0 or any(
            b in low
            for b in (
                "already",
                "duplicate",
                "exist",
                "409",
                "conflict",
                "not modified",
                "unchanged",
            )
        ):
            print(f"CLI App Groups OK em {identifier} ('{cap}').")
            return True
        print(f"Tentativa CLI '{cap}' falhou: {out[:300]}")
    print(f"ERRO CLI App Groups em {identifier}:", (last_out or "")[:700])
    return False


def _disable_app_groups_cli(bundle_rid: str, identifier: str) -> None:
    for cap in CAP_CANDIDATES:
        ec = _run(
            [
                "app-store-connect",
                "bundle-ids",
                "disable-capabilities",
                bundle_rid,
                "--capability",
                cap,
            ]
        )
        out = ((ec.stderr or "") + (ec.stdout or "")).strip()
        low = out.lower()
        if ec.returncode == 0 or any(
            b in low for b in ("not enabled", "not found", "does not exist", "404")
        ):
            print(f"CLI disable App Groups em {identifier} (ok).")
            return
    print(f"AVISO: disable App Groups em {identifier} sem confirmação.")


def _assign_app_group_to_bundle(bundle_rid: str, identifier: str, *, use_api: bool) -> bool:
    if _has_app_groups_with_target(bundle_rid):
        print(f"OK: {identifier} já tem App Groups + {APP_GROUP}")
        return True

    # Força refresh: desliga e religa capability via CLI (mesma auth que SiWA/Push).
    _disable_app_groups_cli(bundle_rid, identifier)
    time.sleep(2)
    if not _enable_via_cli(bundle_rid, identifier):
        return False

    if use_api:
        cap_id = _find_app_groups_capability_id(bundle_rid)
        if cap_id:
            _patch_app_groups_capability(cap_id)
        else:
            _create_app_groups_capability_api(bundle_rid)

        if not _has_app_groups_with_target(bundle_rid):
            cap_id = _find_app_groups_capability_id(bundle_rid)
            if cap_id:
                _patch_app_groups_capability(cap_id)

    if _has_app_groups_capability(_capability_blob(bundle_rid)):
        if APP_GROUP in _capability_blob(bundle_rid):
            print(f"Verificado: {identifier} → App Groups + {APP_GROUP}")
            return True
        print(
            f"AVISO: App Groups ativo em {identifier}, mas grupo {APP_GROUP} "
            "não visível na API — perfil pode herdar do portal Apple."
        )
        return True

    print(f"ERRO: App Groups não confirmado em {identifier}")
    print(_capability_blob(bundle_rid)[:5000])
    return False


def main() -> int:
    print("=== App Groups definitivo (registro + associação) ===")
    print("App Group alvo:", APP_GROUP)
    print("Bundles:", ", ".join(BUNDLES))

    use_api = _ensure_app_group_registered_api()
    if not use_api:
        print(
            "AVISO: registro App Group via API falhou — seguindo só com CLI "
            "(grupo deve existir no portal Apple Developer)."
        )

    time.sleep(3)
    ok_all = True
    for identifier in BUNDLES:
        rid = _bundle_resource_id(identifier)
        if not rid:
            ok_all = False
            continue
        if not _assign_app_group_to_bundle(rid, identifier, use_api=use_api):
            ok_all = False

    if not ok_all:
        print("ERRO: App Groups incompleto em um ou mais bundle IDs.")
        return 1

    print("OK: App Groups configurado no app + Widget.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
