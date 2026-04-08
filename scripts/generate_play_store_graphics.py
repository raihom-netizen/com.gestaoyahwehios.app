"""
Gera ícone 512x512 (RGBA, fundo transparente) e recurso gráfico 1024x500 para a Play Store.
Uso: python generate_play_store_graphics.py
Requer: pip install pillow
"""
from __future__ import annotations

import os
import sys

try:
    from PIL import Image
except ImportError:
    print("Instale Pillow: pip install pillow", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC_ICON = os.path.join(ROOT, "flutter_app", "assets", "icon", "app_icon.png")
OUT_DIR = r"D:\temporarios"
PLAY_ICON_SIZE = 512
FEATURE_W, FEATURE_H = 1024, 500


def ensure_out_dir() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)


def make_play_icon_512() -> str:
    img = Image.open(SRC_ICON).convert("RGBA")
    # Encaixa mantendo proporção dentro de 512x512, fundo transparente
    img.thumbnail((PLAY_ICON_SIZE, PLAY_ICON_SIZE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (PLAY_ICON_SIZE, PLAY_ICON_SIZE), (0, 0, 0, 0))
    x = (PLAY_ICON_SIZE - img.width) // 2
    y = (PLAY_ICON_SIZE - img.height) // 2
    canvas.paste(img, (x, y), img)
    out = os.path.join(OUT_DIR, "gestao_yahweh_play_icon_512_sem_fundo.png")
    canvas.save(out, "PNG", optimize=True)
    return out


def make_feature_graphic() -> str:
    """Fundo em gradiente azul (tema app) + logótipo centrado."""
    # Gradiente vertical: #0c3b8a (topo) -> #e0f2fe (base)
    strip = Image.new("RGB", (1, FEATURE_H))
    for y in range(FEATURE_H):
        t = y / max(FEATURE_H - 1, 1)
        r = int(12 + (224 - 12) * t)
        g = int(59 + (242 - 59) * t)
        b = int(138 + (254 - 138) * t)
        strip.putpixel((0, y), (r, g, b))
    bg = strip.resize((FEATURE_W, FEATURE_H), Image.Resampling.NEAREST)
    bg = bg.convert("RGBA")

    logo = Image.open(SRC_ICON).convert("RGBA")
    # Altura máxima ~72% da feature para margem
    max_h = int(FEATURE_H * 0.72)
    ratio = max_h / logo.height
    new_w = int(logo.width * ratio)
    new_h = int(logo.height * ratio)
    logo = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)

    lx = (FEATURE_W - logo.width) // 2
    ly = (FEATURE_H - logo.height) // 2
    bg.paste(logo, (lx, ly), logo)

    out = os.path.join(OUT_DIR, "gestao_yahweh_feature_graphic_1024x500.png")
    bg.save(out, "PNG", optimize=True)
    return out


def main() -> None:
    if not os.path.isfile(SRC_ICON):
        print(f"Ícone origem não encontrado: {SRC_ICON}", file=sys.stderr)
        sys.exit(1)
    ensure_out_dir()
    p1 = make_play_icon_512()
    p2 = make_feature_graphic()
    print("OK:")
    print(" ", p1)
    print(" ", p2)


if __name__ == "__main__":
    main()
