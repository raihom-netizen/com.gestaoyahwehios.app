#!/usr/bin/env python3
"""
Alinha entitlements App Groups com o que o perfil App Store realmente tem.

A ASC API nao marca group.com… no App ID → perfis nascem com
application-groups: []. Se o perfil NAO tiver o grupo, remove a entitlement
dos plists para o codesign nao falhar (IPA sobe; partilha Widget fica
desligada ate o grupo ser marcado no portal).

Se o perfil TIVER o grupo, nao mexe nos entitlements.
"""
from __future__ import annotations

import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

APP_GROUP = (
    os.environ.get("APP_GROUP_ID") or "group.com.gestaoyahwehios.app.widget"
).strip()
WIDGET_BUNDLE = (
    os.environ.get("WIDGET_BUNDLE_ID")
    or "com.gestaoyahwehios.app.GestaoYahwehWidget"
).strip()
MAIN_BUNDLE = (
    os.environ.get("BUNDLE_ID") or "com.gestaoyahwehios.app"
).strip()

FLAG = Path("/tmp/cm_app_groups_entitlements_stripped")


def _ios_root() -> Path:
    root = Path(os.environ.get("CM_BUILD_DIR") or os.environ.get("FCI_BUILD_DIR") or os.getcwd())
    layout = Path("/tmp/cm_yw_layout")
    kind = layout.read_text(encoding="utf-8").strip() if layout.is_file() else "mono"
    if kind == "root" and (root / "ios").is_dir():
        return root / "ios"
    if (root / "flutter_app" / "ios").is_dir():
        return root / "flutter_app" / "ios"
    return root / "ios"


def _iter_profiles() -> list[dict]:
    out: list[dict] = []
    homes = [
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    ]
    for d in homes:
        if not d.is_dir():
            continue
        for path in d.glob("*.mobileprovision"):
            r = subprocess.run(
                ["security", "cms", "-D", "-i", str(path)],
                capture_output=True,
                check=False,
            )
            if r.returncode != 0:
                continue
            try:
                pl = plistlib.loads(r.stdout)
            except Exception:
                continue
            out.append(pl)
    # Tambem /tmp
    for p in (Path("/tmp/cm_prov.plist"), Path("/tmp/cm_widget_prov.plist")):
        if p.is_file():
            try:
                with p.open("rb") as f:
                    out.append(plistlib.load(f))
            except Exception:
                pass
    return out


def _profile_has_group(bundle_suffix: str) -> bool:
    for pl in _iter_profiles():
        ent = pl.get("Entitlements") or {}
        app_id = str(ent.get("application-identifier") or "")
        if not app_id.endswith(bundle_suffix):
            continue
        groups = ent.get("com.apple.security.application-groups") or []
        if APP_GROUP in groups:
            return True
    return False


def _strip_app_groups_from_entitlements(path: Path) -> bool:
    if not path.is_file():
        return False
    raw = path.read_bytes()
    try:
        data = plistlib.loads(raw)
    except Exception:
        # Fallback XML textual
        text = raw.decode("utf-8", errors="replace")
        if "com.apple.security.application-groups" not in text:
            return False
        # Remove key + array block
        new = re.sub(
            r"\t*<key>com\.apple\.security\.application-groups</key>\s*"
            r"<array>.*?</array>\s*",
            "",
            text,
            flags=re.S,
        )
        if new == text:
            return False
        path.write_text(new, encoding="utf-8")
        print(f"OK: removido application-groups (XML) de {path}")
        return True

    if "com.apple.security.application-groups" not in data:
        return False
    del data["com.apple.security.application-groups"]
    # Prefer XML plist legivel
    path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
    print(f"OK: removido application-groups de {path}")
    return True


def main() -> int:
    ios = _ios_root()
    runner_ent = ios / "Runner" / "Runner.entitlements"
    widget_ent = ios / "GestaoYahwehWidget" / "GestaoYahwehWidget.entitlements"

    runner_ok = _profile_has_group(MAIN_BUNDLE)
    widget_ok = _profile_has_group(WIDGET_BUNDLE)
    print(f"Perfil Runner tem {APP_GROUP}: {runner_ok}")
    print(f"Perfil Widget tem {APP_GROUP}: {widget_ok}")

    stripped = False
    if not runner_ok:
        stripped = _strip_app_groups_from_entitlements(runner_ent) or stripped
    if not widget_ok:
        stripped = _strip_app_groups_from_entitlements(widget_ent) or stripped

    if stripped:
        FLAG.write_text("1\n", encoding="utf-8")
        print(
            "AVISO: App Groups removidos dos entitlements para o codesign "
            "bater com o perfil (ASC nao marca o grupo no App ID)."
        )
        print(
            "  Para reativar partilha Widget: marque o grupo no Apple Developer "
            f"→ Identifiers → App/Widget → App Groups → {APP_GROUP}, "
            "regenere perfis, e volte a fazer Start."
        )
    else:
        if FLAG.exists():
            FLAG.unlink()
        print("OK: perfis incluem App Group — entitlements intactos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
