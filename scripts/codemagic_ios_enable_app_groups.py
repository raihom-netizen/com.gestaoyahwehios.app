"""
Ativa App Groups no App ID principal e no Widget — passo unico, sem retries.

Realidade ASC (2026):
- GET /appGroups → 404 (endpoint removido)
- PATCH settings com APP_GROUP_IDS → 409 (so ICLOUD_VERSION e aceite em settings)
- A API so consegue LIGAR a capability APP_GROUPS (settings fica null)
- A selecao do group.com… no portal NAO e exposivel/alteravel via Connect API
- Criterio de sucesso CI: capability APP_GROUPS presente nos dois Bundle IDs

O group.com… continua a ser exigido depois, no perfil .mobileprovision
(application-groups), ao criar/validar o perfil App Store.
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

APP_GROUP = os.environ.get("APP_GROUP_ID", "group.com.gestaoyahwehios.app.widget").strip()
APP_GROUP_NAME = os.environ.get("APP_GROUP_NAME", "Gestao Yahweh Widget").strip()
BUNDLES = [
    os.environ.get("BUNDLE_ID", "com.gestaoyahwehios.app").strip(),
    os.environ.get("WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget").strip(),
]
CAP_CANDIDATES = ("APP_GROUPS", "App Groups")


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True)


def _exact_bundle_from_api(identifier: str) -> str | None:
    """Resolve Bundle ID com match EXATO (filter ASC e prefixo — Widget vinha primeiro)."""
    try:
        listed = api_request(
            "GET",
            f"/bundleIds?filter[identifier]={identifier}&filter[platform]=IOS&limit=50",
        )
    except RuntimeError as e:
        print(f"AVISO API bundleIds list: {str(e)[:300]}")
        listed = None

    data = (listed or {}).get("data") or []
    for item in data:
        if not isinstance(item, dict):
            continue
        attrs = item.get("attributes") or {}
        if str(attrs.get("identifier") or "") == identifier:
            rid = item.get("id")
            print(f"Bundle ID {identifier} → resource id {rid} (API exact)")
            return str(rid) if rid else None

    # Sem platform filter (alguns tenants usam UNIVERSAL).
    try:
        listed = api_request(
            "GET",
            f"/bundleIds?filter[identifier]={identifier}&limit=50",
        )
    except RuntimeError:
        listed = None
    for item in (listed or {}).get("data") or []:
        attrs = (item or {}).get("attributes") or {}
        if str(attrs.get("identifier") or "") == identifier:
            rid = item.get("id")
            print(f"Bundle ID {identifier} → resource id {rid} (API exact universal)")
            return str(rid) if rid else None
    return None


def _bundle_resource_id(identifier: str) -> str | None:
    rid = _exact_bundle_from_api(identifier)
    if rid:
        return rid

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
    if r.returncode == 0:
        try:
            j = json.loads((r.stdout or "").strip() or "null")
        except json.JSONDecodeError:
            j = None
        data = j.get("data") if isinstance(j, dict) else (j if isinstance(j, list) else [])
        if data and isinstance(data[0], dict):
            attrs = data[0].get("attributes") or {}
            if str(attrs.get("identifier") or "") == identifier or not attrs:
                found = data[0].get("id")
                print(f"Bundle ID {identifier} → resource id {found} (CLI)")
                return found

    print(f"AVISO: Bundle ID nao encontrado: {identifier} — a criar via API...")
    return _create_bundle_id_api(identifier)


def _create_bundle_id_api(identifier: str) -> str | None:
    name = "Gestao Yahweh Widget" if identifier.endswith("GestaoYahwehWidget") else (
        identifier.replace(".", " ")[-50:]
    )
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
            time.sleep(2)
            return _exact_bundle_from_api(identifier)
        print("ERRO criar Bundle ID:", identifier, str(e)[:500])
        return None


def _list_bundle_capabilities(bundle_rid: str) -> list[dict]:
    try:
        detail = api_request(
            "GET",
            f"/bundleIds/{bundle_rid}?include=bundleIdCapabilities",
        )
        included = (detail or {}).get("included") or []
        caps = [
            item
            for item in included
            if isinstance(item, dict) and item.get("type") == "bundleIdCapabilities"
        ]
        if caps:
            return caps
    except RuntimeError as e:
        print("AVISO API include capabilities:", str(e)[:300])

    try:
        listed = api_request(
            "GET",
            f"/bundleIds/{bundle_rid}/bundleIdCapabilities",
        )
        data = (listed or {}).get("data") or []
        if data:
            return data
    except RuntimeError as e:
        print("AVISO API capabilities:", str(e)[:300])

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


def _has_app_groups_capability(bundle_rid: str) -> bool:
    blob = json.dumps(_list_bundle_capabilities(bundle_rid), ensure_ascii=False)
    return bool(re.search(r"APP_GROUPS|App Groups", blob, re.I))


def _enable_app_groups_api(bundle_rid: str) -> bool:
    """Liga APP_GROUPS sem settings (unico formato aceite pela ASC atual)."""
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "APP_GROUPS",
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
        print(f"POST APP_GROUPS (sem settings) em {bundle_rid}")
        return True
    except RuntimeError as e:
        low = str(e).lower()
        if "409" in low or any(x in low for x in ("already", "duplicate", "exist", "conflict")):
            print(f"APP_GROUPS ja activo em {bundle_rid}")
            return True
        print(f"AVISO POST APP_GROUPS: {str(e)[:500]}")
        return False


def _enable_via_cli(bundle_rid: str, identifier: str) -> bool:
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
    return False


def ensure_app_groups_on_bundle(bundle_rid: str, identifier: str) -> bool:
    """Uma passagem: se APP_GROUPS ja existe → OK; senao liga via API/CLI."""
    if _has_app_groups_capability(bundle_rid):
        print(f"OK: {identifier} ja tem capability APP_GROUPS")
        return True

    print(f"--- {identifier}: a ativar APP_GROUPS (passo unico) ---")
    _enable_app_groups_api(bundle_rid)
    if _has_app_groups_capability(bundle_rid):
        print(f"OK: {identifier} → APP_GROUPS activo")
        return True

    _enable_via_cli(bundle_rid, identifier)
    time.sleep(2)
    if _has_app_groups_capability(bundle_rid):
        print(f"OK: {identifier} → APP_GROUPS activo (CLI)")
        return True

    print(f"ERRO: nao foi possivel ativar APP_GROUPS em {identifier}")
    print(json.dumps(_list_bundle_capabilities(bundle_rid), ensure_ascii=False)[:2000])
    return False


# Compat com ensure_widget_appstore_profile (import antigo).
def _resolve_app_group_resource_id() -> str | None:
    """Endpoint /appGroups foi removido da ASC — devolve None sem falhar."""
    print(
        f"INFO: ASC ja nao expoe /appGroups; grupo alvo continua {APP_GROUP} "
        "(confirmacao no perfil .mobileprovision)."
    )
    if APP_GROUP_NAME:
        pass
    return None


def assign_app_group_to_bundle(
    bundle_rid: str,
    identifier: str,
    *,
    app_group_rid: str | None = None,
    max_rounds: int = 1,
) -> bool:
    """Compat: ignora app_group_rid/max_rounds — so garante capability APP_GROUPS."""
    _ = (app_group_rid, max_rounds)
    return ensure_app_groups_on_bundle(bundle_rid, identifier)


def ensure_bundles(bundles: list[str] | None = None) -> bool:
    targets = [b for b in (bundles or BUNDLES) if b]
    print("=== App Groups (capability only, sem retries) ===")
    print("App Group alvo (perfil):", APP_GROUP)
    print("Bundles:", ", ".join(targets))
    print(
        "Nota: Apple rejeita APP_GROUP_IDS em settings; nao ha loop DELETE/PATCH."
    )

    ok_all = True
    for identifier in targets:
        rid = _bundle_resource_id(identifier)
        if not rid:
            ok_all = False
            continue
        if not ensure_app_groups_on_bundle(rid, identifier):
            ok_all = False

    if not ok_all:
        print("ERRO: APP_GROUPS incompleto em um ou mais bundle IDs.")
        return False

    print("OK: APP_GROUPS activo no app + Widget (selecao group.com no portal/perfil).")
    return True


def main() -> int:
    only = (os.environ.get("APP_GROUPS_ONLY_BUNDLE") or "").strip()
    bundles = [only] if only else None
    return 0 if ensure_bundles(bundles) else 1


if __name__ == "__main__":
    sys.exit(main())
