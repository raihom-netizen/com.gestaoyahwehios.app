"""
Registra App Group, associa ao App ID principal e ao Widget — de forma estrita.

Causa raiz do falhanço Codemagic: capability APP_GROUPS activa sem o
group.com… seleccionado → perfil IOS_APP_STORE com application-groups: [].

Este script FALHA se o grupo alvo não ficar confirmado na capability
(não aceita «AVISO» como sucesso).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_asc_api import api_request  # noqa: E402

APP_GROUP = os.environ.get("APP_GROUP_ID", "group.com.gestaoyahwehios.app.widget").strip()
APP_GROUP_NAME = os.environ.get("APP_GROUP_NAME", "Gestao Yahweh Widget").strip()
BUNDLES = [
    os.environ.get("BUNDLE_ID", "com.gestaoyahwehios.app").strip(),
    os.environ.get("WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget").strip(),
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


def _resolve_app_group_resource_id() -> str | None:
    """Garante App Group registado e devolve o resource id ASC."""
    try:
        listed = api_request(
            "GET",
            f"/appGroups?filter[identifier]={APP_GROUP}&limit=5",
        )
        data = (listed or {}).get("data") or []
        if data:
            gid = data[0].get("id")
            print(f"OK: App Group já registrado: {APP_GROUP} (id={gid})")
            return str(gid) if gid else None
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
        return str(gid) if gid else None
    except RuntimeError as e:
        low = str(e).lower()
        if any(x in low for x in ("already", "duplicate", "409", "exists", "not unique")):
            try:
                listed = api_request(
                    "GET",
                    f"/appGroups?filter[identifier]={APP_GROUP}&limit=5",
                )
                data = (listed or {}).get("data") or []
                if data:
                    return str(data[0].get("id") or "") or None
            except RuntimeError:
                pass
            print(f"App Group {APP_GROUP} já existe (API) mas id não lido.")
            return None
        print("ERRO POST appGroups:", str(e)[:600])
        return None


def _settings_variants(app_group_rid: str | None) -> list[list[dict[str, Any]]]:
    """Apple aceita identifier group.com… e/ou o resource id do App Group."""
    keys: list[str] = [APP_GROUP]
    if app_group_rid and app_group_rid not in keys:
        keys.append(app_group_rid)
    # Também tenta ambos na mesma capability (alguns tenants ASC preferem o id).
    variants: list[list[dict[str, Any]]] = []
    for k in keys:
        variants.append(
            [
                {
                    "key": "APP_GROUP_IDS",
                    "options": [{"key": k, "enabled": True}],
                }
            ]
        )
    if app_group_rid and app_group_rid != APP_GROUP:
        variants.append(
            [
                {
                    "key": "APP_GROUP_IDS",
                    "options": [
                        {"key": APP_GROUP, "enabled": True},
                        {"key": app_group_rid, "enabled": True},
                    ],
                }
            ]
        )
    return variants


def _list_bundle_capabilities(bundle_rid: str) -> list[dict]:
    """Lista capabilities. Apple rejeita ?limit=… neste related endpoint (PARAMETER_ERROR.ILLEGAL)."""
    # 1) include= no recurso bundleId — caminho estável pós-mudança ASC 2025/2026.
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

    # 2) Related sem query params ilegais.
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

    # 3) CLI (pode omitir settings / APP_GROUPS em alguns tenants).
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
    return json.dumps(_list_bundle_capabilities(bundle_rid), ensure_ascii=False)


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
    # ASC costuma usar id estável {bundleResourceId}_APP_GROUPS (ex.: 4CRV3URU4Z_IN_APP_PURCHASE).
    return f"{bundle_rid}_APP_GROUPS"


def _delete_app_groups_capability(cap_id: str) -> None:
    try:
        api_request("DELETE", f"/bundleIdCapabilities/{cap_id}", ok_status=(204, 200))
        print(f"DELETE bundleIdCapabilities/{cap_id}")
    except RuntimeError as e:
        print(f"AVISO DELETE capability: {str(e)[:400]}")


def _create_app_groups_with_settings(
    bundle_rid: str, settings: list[dict[str, Any]]
) -> bool:
    """True se criou OU se já existia (caller deve PATCH settings no 409)."""
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "attributes": {
                "capabilityType": "APP_GROUPS",
                "settings": settings,
            },
            "relationships": {
                "bundleId": {
                    "data": {"type": "bundleIds", "id": bundle_rid},
                }
            },
        }
    }
    try:
        created = api_request(
            "POST", "/bundleIdCapabilities", body=body, ok_status=(200, 201)
        )
        print(f"POST APP_GROUPS + settings em bundle {bundle_rid}")
        # Confirmação imediata pelo corpo da resposta (evita listagem incompleta).
        blob = json.dumps(created or {}, ensure_ascii=False)
        if APP_GROUP in blob:
            return True
        return True
    except RuntimeError as e:
        low = str(e).lower()
        if "409" in low or any(
            x in low for x in ("already", "duplicate", "exist", "conflict")
        ):
            print(f"POST APP_GROUPS já existia em {bundle_rid} — a fazer PATCH settings")
            cap_id = _find_app_groups_capability_id(bundle_rid)
            if cap_id and _patch_app_groups_with_settings(cap_id, settings):
                return True
            return False
        print(f"ERRO POST capability: {str(e)[:700]}")
        return False


def _patch_app_groups_with_settings(cap_id: str, settings: list[dict[str, Any]]) -> bool:
    # Só settings (padrão Spaceship/CT) — capabilityType no PATCH pode falhar em alguns tenants.
    body = {
        "data": {
            "type": "bundleIdCapabilities",
            "id": cap_id,
            "attributes": {
                "settings": settings,
            },
        }
    }
    try:
        patched = api_request("PATCH", f"/bundleIdCapabilities/{cap_id}", body=body)
        print(f"PATCH bundleIdCapabilities/{cap_id} com settings")
        blob = json.dumps(patched or {}, ensure_ascii=False)
        if APP_GROUP in blob or patched is not None:
            return True
        return True
    except RuntimeError as e:
        # Fallback: incluir capabilityType (schema antigo).
        body2 = {
            "data": {
                "type": "bundleIdCapabilities",
                "id": cap_id,
                "attributes": {
                    "capabilityType": "APP_GROUPS",
                    "settings": settings,
                },
            }
        }
        try:
            api_request("PATCH", f"/bundleIdCapabilities/{cap_id}", body=body2)
            print(f"PATCH bundleIdCapabilities/{cap_id} (com capabilityType) OK")
            return True
        except RuntimeError as e2:
            print(f"AVISO PATCH capability: {str(e)[:400]} | retry: {str(e2)[:400]}")
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


def assign_app_group_to_bundle(
    bundle_rid: str,
    identifier: str,
    *,
    app_group_rid: str | None,
    max_rounds: int = 4,
) -> bool:
    """Associa APP_GROUP ao App ID. Retorna True só se o grupo aparecer na capability."""
    if _has_app_groups_with_target(bundle_rid):
        print(f"OK: {identifier} já tem App Groups + {APP_GROUP}")
        return True

    variants = _settings_variants(app_group_rid)

    # Round 0: PATCH/POST sem apagar (evita estado em que CLI lista só IN_APP_PURCHASE).
    settings0 = variants[0]
    print(f"--- {identifier}: round 0/{max_rounds} (PATCH/POST sem delete) ---")
    cap_id0 = _find_app_groups_capability_id(bundle_rid)
    if cap_id0:
        _patch_app_groups_with_settings(cap_id0, settings0)
    _create_app_groups_with_settings(bundle_rid, settings0)
    time.sleep(3)
    if _has_app_groups_with_target(bundle_rid):
        print(f"Verificado: {identifier} → App Groups + {APP_GROUP}")
        return True

    for round_i in range(1, max_rounds + 1):
        print(f"--- {identifier}: round {round_i}/{max_rounds} ---")
        # Limpa capability vazia (APP_GROUPS sem grupo → perfil com application-groups: []).
        cap_id = _find_app_groups_capability_id(bundle_rid)
        if cap_id:
            _delete_app_groups_capability(cap_id)
            time.sleep(2)
        _disable_app_groups_cli(bundle_rid, identifier)
        time.sleep(2)

        settings = variants[(round_i - 1) % len(variants)]
        created = _create_app_groups_with_settings(bundle_rid, settings)
        if not created:
            _enable_via_cli(bundle_rid, identifier)
            time.sleep(2)
            cap_id = _find_app_groups_capability_id(bundle_rid)
            if cap_id:
                _patch_app_groups_with_settings(cap_id, settings)
            else:
                _create_app_groups_with_settings(bundle_rid, settings)
        else:
            # Alguns tenants criam capability sem settings — PATCH em seguida.
            time.sleep(2)
            if not _has_app_groups_with_target(bundle_rid):
                cap_id = _find_app_groups_capability_id(bundle_rid)
                if cap_id:
                    _patch_app_groups_with_settings(cap_id, settings)

        time.sleep(3 + round_i * 2)
        if _has_app_groups_with_target(bundle_rid):
            print(f"Verificado: {identifier} → App Groups + {APP_GROUP}")
            return True
        print(f"Ainda sem {APP_GROUP} em {identifier}. Blob:")
        print(_capability_blob(bundle_rid)[:2500])

    print(f"ERRO: App Groups + {APP_GROUP} NÃO confirmado em {identifier}")
    return False


def ensure_bundles(bundles: list[str] | None = None) -> bool:
    targets = [b for b in (bundles or BUNDLES) if b]
    print("=== App Groups definitivo (registro + associação estrita) ===")
    print("App Group alvo:", APP_GROUP)
    print("Bundles:", ", ".join(targets))

    app_group_rid = _resolve_app_group_resource_id()
    if not app_group_rid:
        print(
            "AVISO: resource id do App Group não obtido — a tentar só com identifier."
        )

    time.sleep(2)
    ok_all = True
    for identifier in targets:
        rid = _bundle_resource_id(identifier)
        if not rid:
            ok_all = False
            continue
        if not assign_app_group_to_bundle(
            rid, identifier, app_group_rid=app_group_rid
        ):
            ok_all = False

    if not ok_all:
        print("ERRO: App Groups incompleto em um ou mais bundle IDs.")
        return False

    print("OK: App Groups configurado (grupo confirmado) no app + Widget.")
    return True


def main() -> int:
    only = (os.environ.get("APP_GROUPS_ONLY_BUNDLE") or "").strip()
    bundles = [only] if only else None
    return 0 if ensure_bundles(bundles) else 1


if __name__ == "__main__":
    sys.exit(main())
