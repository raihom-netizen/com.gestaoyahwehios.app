#!/usr/bin/env python3
"""
Alinha Push (aps-environment + UIBackgroundModes remote-notification) com o perfil.

Se o perfil App Store do Runner NAO tiver aps-environment:
  - remove aps-environment de Runner.entitlements (codesign)
  - remove remote-notification de Info.plist (evita «Binário inválido» no TestFlight)

Se o perfil TIVER aps-environment, garante remote-notification no Info.plist.
"""
from __future__ import annotations

import os
import plistlib
import subprocess
import sys
from pathlib import Path

MAIN_BUNDLE = (os.environ.get("BUNDLE_ID") or "com.gestaoyahwehios.app").strip()
FLAG = Path("/tmp/cm_push_entitlements_stripped")


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
    for p in (Path("/tmp/cm_prov.plist"), Path("/tmp/cm_raw.mobileprovision")):
        if not p.is_file():
            continue
        if p.suffix == ".plist" or p.name.endswith(".plist"):
            try:
                with p.open("rb") as f:
                    out.append(plistlib.load(f))
            except Exception:
                pass
        else:
            r = subprocess.run(
                ["security", "cms", "-D", "-i", str(p)],
                capture_output=True,
                check=False,
            )
            if r.returncode == 0:
                try:
                    out.append(plistlib.loads(r.stdout))
                except Exception:
                    pass
    return out


def _profile_has_aps() -> bool:
    for pl in _iter_profiles():
        ent = pl.get("Entitlements") or {}
        app_id = str(ent.get("application-identifier") or "")
        if not app_id.endswith(MAIN_BUNDLE):
            continue
        if "aps-environment" in ent:
            return True
    return False


def _set_aps_entitlement(path: Path, enable: bool) -> bool:
    if not path.is_file():
        return False
    data = plistlib.loads(path.read_bytes())
    changed = False
    if enable:
        if data.get("aps-environment") != "production":
            data["aps-environment"] = "production"
            changed = True
    else:
        if "aps-environment" in data:
            del data["aps-environment"]
            changed = True
    if changed:
        path.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
        print(f"OK: aps-environment {'= production' if enable else 'removido'} em {path}")
    return changed


def _set_remote_notification(info_plist: Path, enable: bool) -> bool:
    if not info_plist.is_file():
        return False
    data = plistlib.loads(info_plist.read_bytes())
    modes = list(data.get("UIBackgroundModes") or [])
    has = "remote-notification" in modes
    changed = False
    if enable and not has:
        modes.append("remote-notification")
        data["UIBackgroundModes"] = modes
        changed = True
    elif (not enable) and has:
        modes = [m for m in modes if m != "remote-notification"]
        if modes:
            data["UIBackgroundModes"] = modes
        else:
            data.pop("UIBackgroundModes", None)
        changed = True
    if changed:
        info_plist.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_XML))
        print(
            f"OK: remote-notification {'adicionado' if enable else 'removido'} em {info_plist}"
        )
    return changed


def main() -> int:
    ios = _ios_root()
    runner_ent = ios / "Runner" / "Runner.entitlements"
    info_plist = ios / "Runner" / "Info.plist"

    has_aps = _profile_has_aps()
    print(f"Perfil Runner tem aps-environment: {has_aps}")

    if has_aps:
        _set_aps_entitlement(runner_ent, True)
        _set_remote_notification(info_plist, True)
        if FLAG.exists():
            FLAG.unlink()
        print("OK: Push alinhado (perfil + entitlements + Info.plist).")
        return 0

    stripped = False
    stripped = _set_aps_entitlement(runner_ent, False) or stripped
    stripped = _set_remote_notification(info_plist, False) or stripped
    FLAG.write_text("1\n", encoding="utf-8")
    print(
        "AVISO: perfil sem Push — removidos aps-environment e remote-notification "
        "para o IPA passar na validação ASC."
    )
    print(
        "  Para FCM em background no iPhone: ative Push Notifications no App ID, "
        "regenere o perfil App Store (ou deixe o CI recriar), e Start de novo."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
