"""
Gera ExportOptions.plist com perfis explícitos (app + Widget) para exportArchive.
Match EXATO de bundle — evita usar perfil Widget no app principal.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_ios_profile_utils import (  # noqa: E402
    find_profile_for_bundle,
    profile_bundle_id,
)

BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.gestaoyahwehios.app")
WIDGET_BUNDLE_ID = os.environ.get(
    "WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget"
)
APP_GROUP = os.environ.get("APP_GROUP_ID", "group.com.gestaoyahwehios.app.widget")
STRIPPED = Path("/tmp/cm_app_groups_entitlements_stripped").is_file()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-o",
        "--output",
        default="ios/ExportOptions.plist",
        help="Caminho do ExportOptions.plist (relativo ao flutter_app)",
    )
    args = parser.parse_args()

    # Preferir perfil com App Group; se ASC nao marcou o grupo, aceitar sem.
    require_group = None if STRIPPED else APP_GROUP
    main_hit = find_profile_for_bundle(
        BUNDLE_ID,
        require_app_group=require_group,
        require_sign_in_apple=True,
    )
    if main_hit is None:
        main_hit = find_profile_for_bundle(
            BUNDLE_ID,
            require_app_group=None,
            require_sign_in_apple=True,
        )
    if main_hit is None:
        main_hit = find_profile_for_bundle(BUNDLE_ID, require_app_group=None)
    if main_hit is None:
        print(f"ERRO: perfil App Store nao encontrado para {BUNDLE_ID} (match exato).")
        return 1

    widget_hit = find_profile_for_bundle(
        WIDGET_BUNDLE_ID,
        require_app_group=require_group,
    )
    if widget_hit is None:
        widget_hit = find_profile_for_bundle(
            WIDGET_BUNDLE_ID,
            require_app_group=None,
        )
    if widget_hit is None:
        print(f"ERRO: perfil Widget nao encontrado para {WIDGET_BUNDLE_ID}.")
        return 1

    main_name, main_uuid, main_pl = main_hit
    widget_name, widget_uuid, widget_pl = widget_hit

    if main_name == widget_name or main_uuid == widget_uuid:
        print("ERRO: mesmo perfil atribuido ao app e ao Widget — abortando export.")
        return 1

    main_suffix = profile_bundle_id(main_pl)
    widget_suffix = profile_bundle_id(widget_pl)
    if main_suffix != BUNDLE_ID:
        print(f"ERRO: perfil app aponta para {main_suffix}, esperado {BUNDLE_ID}")
        return 1
    if widget_suffix != WIDGET_BUNDLE_ID:
        print(f"ERRO: perfil widget aponta para {widget_suffix}, esperado {WIDGET_BUNDLE_ID}")
        return 1

    print(f"Perfil app: {main_name}")
    print(f"  bundle: {main_suffix} | uuid: {main_uuid}")
    print(f"Perfil widget: {widget_name}")
    print(f"  bundle: {widget_suffix} | uuid: {widget_uuid}")
    if STRIPPED:
        print("AVISO: ExportOptions sem exigir App Group (entitlements alinhados).")

    export_plist = {
        "method": "app-store",
        "signingStyle": "manual",
        "uploadSymbols": True,
        "compileBitcode": False,
        "provisioningProfiles": {
            BUNDLE_ID: main_name,
            WIDGET_BUNDLE_ID: widget_name,
        },
    }

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "wb") as f:
        plistlib.dump(export_plist, f)
    print(f"ExportOptions.plist gravado: {out_path.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
