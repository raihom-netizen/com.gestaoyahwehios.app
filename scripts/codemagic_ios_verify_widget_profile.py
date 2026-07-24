"""
Valida perfil App Store da extensão Widget (bundle exato).
App Group: preferivel, mas nao hard-fail se entitlements foram alinhados.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from codemagic_ios_profile_utils import (  # noqa: E402
    find_profile_for_bundle,
    profile_bundle_id,
)

WIDGET_BUNDLE = os.environ.get(
    "WIDGET_BUNDLE_ID", "com.gestaoyahwehios.app.GestaoYahwehWidget"
)
APP_GROUP = os.environ.get("APP_GROUP_ID", "group.com.gestaoyahwehios.app.widget")
MAIN_BUNDLE = os.environ.get("BUNDLE_ID", "com.gestaoyahwehios.app")
STRIPPED = Path("/tmp/cm_app_groups_entitlements_stripped").is_file()


def main() -> int:
    widget_hit = find_profile_for_bundle(
        WIDGET_BUNDLE,
        require_app_group=APP_GROUP if not STRIPPED else None,
    )
    if widget_hit is None:
        # Sem exigir grupo
        widget_hit = find_profile_for_bundle(WIDGET_BUNDLE, require_app_group=None)
    if widget_hit is None:
        print(f"ERRO: perfil Widget nao encontrado ({WIDGET_BUNDLE}).")
        return 1

    name, uuid, pl = widget_hit
    suffix = profile_bundle_id(pl)
    groups = (pl.get("Entitlements") or {}).get("com.apple.security.application-groups") or []
    print(f"Perfil Widget: {name} ({uuid})")
    print(f"  bundle exato: {suffix}")
    print(f"  application-groups: {groups}")

    if suffix != WIDGET_BUNDLE:
        print(f"ERRO: bundle do perfil ({suffix}) != {WIDGET_BUNDLE}")
        return 1
    if APP_GROUP not in groups:
        if STRIPPED:
            print(
                f"AVISO: grupo {APP_GROUP} ausente no perfil — OK (entitlements alinhados)."
            )
        else:
            print(
                f"AVISO: grupo {APP_GROUP} ausente — rode align entitlements antes do archive."
            )

    main_hit = find_profile_for_bundle(MAIN_BUNDLE)
    if main_hit and main_hit[0] == name:
        print("ERRO: perfil do app principal e o mesmo do Widget.")
        return 1

    print("OK: perfil Widget pronto para ExportOptions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
