"""Ícones de módulo Gestão YAHWEH — padrão Controle Total (emblema + badge premium).

Gera PNGs em assets/icon/ para: avisos, eventos, escalas, contas a pagar,
novo membro e aniversariantes.

Uso:
  python tool/generate_yahweh_module_icons.py
"""

from __future__ import annotations

import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "assets" / "icon"
SRC = ICON_DIR / "app_icon.png"
OUT_SIZE = 512

# Cores alinhadas a gyModuleAccentColor (gestao_foreground_notification_snackbar.dart)
MODULES = {
    "icon_avisos": {
        "accent": (14, 165, 233),
        "label": "AVISOS",
        "transparent_only": True,
    },
    "icon_eventos": {
        "accent": (249, 115, 22),
        "label": "EVENTOS",
    },
    "icon_escalas": {
        "accent": (20, 184, 166),
        "label": "ESCALAS",
    },
    "icon_contas_pagar": {
        "accent": (220, 38, 38),
        "label": "CONTAS",
    },
    "icon_novo_membro": {
        "accent": (37, 99, 235),
        "label": "MEMBRO",
    },
    "icon_aniversariantes": {
        "accent": (225, 29, 72),
        "label": "ANIV.",
    },
}


def is_removable_background(r: int, g: int, b: int, a: int) -> bool:
    if a < 8:
        return True
    mx = max(r, g, b)
    mn = min(r, g, b)
    sat = mx - mn
    if mx <= 32 and sat <= 24:
        return True
    if mx < 52 and sat < 38:
        return True
    if mn > 238 and sat < 18:
        return True
    if mn > 225 and sat < 28 and abs(r - g) < 12 and abs(g - b) < 12:
        return True
    return False


def remove_border_background(src: Image.Image) -> Image.Image:
    img = src.convert("RGBA")
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    q: deque[tuple[int, int]] = deque()

    def try_enqueue(x: int, y: int) -> None:
        if x < 0 or y < 0 or x >= w or y >= h:
            return
        idx = y * w + x
        if visited[idx]:
            return
        visited[idx] = 1
        r, g, b, a = px[x, y]
        if is_removable_background(r, g, b, a):
            q.append((x, y))

    for x in range(w):
        try_enqueue(x, 0)
        try_enqueue(x, h - 1)
    for y in range(h):
        try_enqueue(0, y)
        try_enqueue(w - 1, y)

    while q:
        x, y = q.popleft()
        r, g, b, _a = px[x, y]
        px[x, y] = (r, g, b, 0)
        try_enqueue(x + 1, y)
        try_enqueue(x - 1, y)
        try_enqueue(x, y + 1)
        try_enqueue(x, y - 1)

    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(radius=0.5))
    img.putalpha(alpha)
    return img


def fit_emblem(emblem: Image.Image, size: int, scale: float) -> Image.Image:
    alpha = emblem.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise RuntimeError("Emblema sem alpha.")
    cropped = emblem.crop(bbox)
    target = int(size * scale)
    fitted = cropped.copy()
    fitted.thumbnail((target, target), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def _lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def gradient_square(accent: tuple[int, int, int], size: int) -> Image.Image:
    dark = tuple(max(0, c - 42) for c in accent)
    light = tuple(min(255, c + 48) for c in accent)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(size - 1, 1)
        row = (
            _lerp(dark[0], light[0], t),
            _lerp(dark[1], light[1], t),
            _lerp(dark[2], light[2], t),
        )
        draw.line([(0, y), (size, y)], fill=row + (255,))
    return img


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_module_glyph(draw: ImageDraw.ImageDraw, key: str, cx: int, cy: int, r: int) -> None:
    white = (255, 255, 255, 255)
    if key == "icon_eventos":
        w, h = r * 2, int(r * 1.7)
        x0, y0 = cx - w // 2, cy - h // 2 + 4
        draw.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=8, outline=white, width=4)
        for i in range(3):
            draw.line((x0 + 12 + i * 18, y0 + 6, x0 + 12 + i * 18, y0 + 18), fill=white, width=3)
        draw.ellipse((cx - 6, cy + 8, cx + 6, cy + 20), fill=white)
    elif key == "icon_escalas":
        cols, rows = 3, 3
        cell = r // 2
        x0 = cx - (cols * cell) // 2
        y0 = cy - (rows * cell) // 2
        for row in range(rows):
            for col in range(cols):
                x = x0 + col * cell + 4
                y = y0 + row * cell + 4
                draw.rounded_rectangle((x, y, x + cell - 8, y + cell - 8), radius=4, fill=white)
    elif key == "icon_contas_pagar":
        w, h = int(r * 1.8), int(r * 2.2)
        x0, y0 = cx - w // 2, cy - h // 2
        draw.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=6, outline=white, width=4)
        draw.line((x0 + 10, y0 + 16, x0 + w - 10, y0 + 16), fill=white, width=3)
        draw.line((x0 + 10, y0 + 28, x0 + w - 18, y0 + 28), fill=white, width=3)
        draw.polygon(
            [(cx + r // 2, cy - r), (cx + r, cy - r // 3), (cx + r // 2, cy)],
            fill=white,
        )
    elif key == "icon_novo_membro":
        draw.ellipse((cx - 14, cy - 28, cx + 14, cy), outline=white, width=4)
        draw.arc((cx - 28, cy - 4, cx + 28, cy + 36), 200, 340, fill=white, width=4)
        draw.line((cx + 22, cy + 18, cx + 38, cy + 18), fill=white, width=4)
        draw.line((cx + 30, cy + 10, cx + 30, cy + 26), fill=white, width=4)
    elif key == "icon_aniversariantes":
        draw.rectangle((cx - 22, cy + 6, cx + 22, cy + 22), fill=white)
        for i, angle in enumerate([-28, 0, 28]):
            rad = math.radians(angle - 90)
            fx = cx + int(math.cos(rad) * 8)
            fy = cy - 8 + int(math.sin(rad) * 8)
            draw.ellipse((fx - 5, fy - 10, fx + 5, fy), fill=(255, 200, 80, 255))
            draw.line((fx, fy, fx, fy + 14), fill=(255, 220, 100, 255), width=2)
    elif key == "icon_avisos":
        draw.polygon(
            [(cx - 20, cy - 8), (cx + 20, cy - 8), (cx + 28, cy + 18), (cx - 28, cy + 18)],
            outline=white,
            width=4,
        )
        draw.rectangle((cx - 6, cy + 18, cx + 6, cy + 30), fill=white)


def make_module_icon(
    emblem: Image.Image,
    key: str,
    meta: dict,
    size: int = OUT_SIZE,
) -> Image.Image:
    if meta.get("transparent_only"):
        return fit_emblem(emblem, size, scale=0.92)

    accent = meta["accent"]
    base = gradient_square(accent, size)
    mask = rounded_mask(size, radius=int(size * 0.18))
    card = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    card.paste(base, (0, 0), mask)

    # Cartão branco interior — padrão Controle Total (logo + badge).
    inset = int(size * 0.08)
    inner = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner_draw = ImageDraw.Draw(inner)
    inner_draw.rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=int(size * 0.12),
        fill=(255, 255, 255, 245),
    )
    card.alpha_composite(inner)

    em = fit_emblem(emblem, size, scale=0.52)
    card.alpha_composite(em, (0, -int(size * 0.04)))

    badge_r = int(size * 0.11)
    bx = size - inset - badge_r - 4
    by = size - inset - badge_r - 4
    badge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(badge)
    bdraw.ellipse(
        (bx - badge_r, by - badge_r, bx + badge_r, by + badge_r),
        fill=accent + (255,),
    )
    bdraw.ellipse(
        (bx - badge_r, by - badge_r, bx + badge_r, by + badge_r),
        outline=(255, 255, 255, 230),
        width=3,
    )
    draw_module_glyph(bdraw, key, bx, by, badge_r - 6)
    card.alpha_composite(badge)

    return card


def main() -> None:
    if not SRC.is_file():
        raise FileNotFoundError(f"Origem não encontrada: {SRC}")

    ICON_DIR.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")
    emblem = remove_border_background(src)
    print(f"Origem: {SRC}")

    for filename, meta in MODULES.items():
        out = ICON_DIR / f"{filename}.png"
        icon = make_module_icon(emblem, filename, meta)
        icon.save(out, "PNG", optimize=True)
        print(f"Gerado: {out} ({meta['label']})")

    # Emblema puro (sem fundo) — reutilizável em UI.
    emblem_only = fit_emblem(emblem, OUT_SIZE, scale=0.92)
    emblem_path = ICON_DIR / "emblema_yahweh_transparent.png"
    emblem_only.save(emblem_path, "PNG", optimize=True)
    print(f"Gerado: {emblem_path}")


if __name__ == "__main__":
    main()
