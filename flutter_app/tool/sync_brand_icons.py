"""Sincroniza ícone oficial Gestão YAHWEH para web/PWA e alias de logo.

Uso:
  python tool/sync_brand_icons.py
  dart run flutter_launcher_icons
"""

from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / "assets" / "icon" / "app_icon.png"
ALIAS = ROOT / "assets" / "LOGO_GESTAO_YAHWEH.png"
WEB_ICONS = ROOT / "web" / "icons"
WEB_FAV = ROOT / "web" / "favicon.png"
WEB_ASSET = ROOT / "web" / "assets" / "images" / "icon.png"
PUBLIC_LOGO = ROOT / "public" / "assets" / "logo.png"


def main() -> None:
    if not ICON.is_file():
        raise FileNotFoundError(f"Ícone principal ausente: {ICON}")

    shutil.copy2(ICON, ALIAS)
    print(f"Sincronizado: {ALIAS}")

    WEB_ICONS.mkdir(parents=True, exist_ok=True)
    for name, size in [
        ("Icon-192.png", 192),
        ("Icon-512.png", 512),
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ]:
        dest = WEB_ICONS / name
        shutil.copy2(ICON, dest)
        print(f"Web icon: {dest} ({size}px source)")

    WEB_FAV.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ICON, WEB_FAV)
    print(f"Favicon: {WEB_FAV}")

    WEB_ASSET.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ICON, WEB_ASSET)
    print(f"Web asset: {WEB_ASSET}")

    if PUBLIC_LOGO.parent.is_dir():
        shutil.copy2(ICON, PUBLIC_LOGO)
        print(f"Public logo: {PUBLIC_LOGO}")


if __name__ == "__main__":
    main()
