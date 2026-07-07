#!/usr/bin/env python3
"""Generate LewisWhisper app + menu bar icons from the Lewis IT Consulting logo.

Outputs:
  assets/icon_1024.png     — macOS app icon master (rounded rect on transparency)
  assets/MenuBarIcon.png   — 36px monochrome soundwave template image (18pt @2x)
"""
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).parent.parent
ASSETS = REPO / "assets"
LOGO = Path("/Users/chadl./Documents/LEWIS IT CONSULTING/Logos/Lewis_IT_Nobackground_Cropped.png")

CANVAS = 1024
INSET = 100          # Apple icon grid: content in an 824px rounded rect
RADIUS = 185


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / (size - 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((size, size))


def soundwave(draw: ImageDraw.ImageDraw, cx: int, cy: int, heights: list, bar_w: int, gap: int, color):
    total = len(heights) * bar_w + (len(heights) - 1) * gap
    x = cx - total // 2
    for h in heights:
        draw.rounded_rectangle([x, cy - h // 2, x + bar_w, cy + h // 2], radius=bar_w // 2, fill=color)
        x += bar_w + gap


def make_app_icon():
    plate_size = CANVAS - 2 * INSET
    plate = vertical_gradient(plate_size, (252, 252, 250), (233, 233, 229)).convert("RGBA")
    plate.putalpha(rounded_rect_mask(plate_size, RADIUS))

    # logo: keep the "Lewis IT" lockup incl. the swash descender, drop the
    # CONSULTING baseline; kill the raster's baked-in soft shadow (low-alpha haze)
    logo = Image.open(LOGO).convert("RGBA")
    # row 140 is the measured boundary: script descenders taper out by ~138,
    # CONSULTING letterforms start at 141 (alpha-channel row analysis)
    logo = logo.crop((0, 0, logo.width, 140))
    r, g, b, a = logo.split()
    a = a.point(lambda v: 0 if v < 48 else v)
    logo = Image.merge("RGBA", (r, g, b, a))
    target_w = int(plate_size * 0.78)
    ratio = target_w / logo.width
    logo = logo.resize((target_w, int(logo.height * ratio)), Image.LANCZOS)

    draw = ImageDraw.Draw(plate)
    logo_y = int(plate_size * 0.31) - logo.height // 2
    plate.alpha_composite(logo, (int((plate_size - target_w) / 2), logo_y))

    # soundwave below the mark — the "voice" element
    heights = [48, 102, 166, 222, 166, 102, 48]
    soundwave(draw, plate_size // 2, int(plate_size * 0.70), heights, bar_w=30, gap=28, color=(20, 20, 20, 255))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(plate, (INSET, INSET))
    ASSETS.mkdir(exist_ok=True)
    canvas.save(ASSETS / "icon_1024.png")
    print("wrote", ASSETS / "icon_1024.png")


def make_menubar_icon():
    # 36px canvas rendered as 18pt @2x; pure black + alpha, isTemplate at runtime
    img = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    soundwave(draw, 18, 18, heights=[8, 16, 26, 32, 26, 16, 8], bar_w=3, gap=2, color=(0, 0, 0, 255))
    img.save(ASSETS / "MenuBarIcon.png")
    print("wrote", ASSETS / "MenuBarIcon.png")


if __name__ == "__main__":
    make_app_icon()
    make_menubar_icon()
