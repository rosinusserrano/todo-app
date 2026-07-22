#!/usr/bin/env python
"""Regenerate the app icon masters under app/assets/.

The artwork is the one the Tauri build shipped (src-tauri/icons/icon.png): a
rounded tile with an indigo->violet gradient and a white checkmark. That file is
only 512px, which is below what iOS wants, so the tile and the gradient are
redrawn from measured geometry at 1024 and only the *checkmark* is carried over
from the original - as an alpha mask, which is the one part that would be
tedious to reproduce by hand and which upscales cleanly because it is a thick,
smooth shape.

Run from app/:  python tool/generate_icons.py
Then:           dart run flutter_launcher_icons

Outputs:
  assets/icon.png             1024 tile on transparency - Windows, Android legacy
  assets/icon_ios.png         1024 full-bleed, opaque - iOS masks its own corners
  assets/icon_adaptive_fg.png 1024 checkmark only, inside Android's safe zone
  assets/tray_icon.ico        multi-size tray icon, tighter padding
  assets/tray_icon.png        32px equivalent, for tray backends wanting a PNG
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

HERE = Path(__file__).resolve().parent
APP = HERE.parent
SOURCE = APP.parent / "src-tauri" / "icons" / "icon.png"
ASSETS = APP / "assets"

SIZE = 1024

# Measured off the 512px original: the tile is inset 9.375% on every side and
# its corner radius is 21.9% of the tile's own width.
TILE_INSET = 0.09375
TILE_RADIUS = 0.219

# See the tray note in main(): the same art, but with most of the padding taken
# back so the glyph survives being drawn at 16px.
TRAY_INSET = 0.03

# Sampled from inside the tile's top-left and bottom-right. The gradient runs
# on the diagonal; red barely moves, green is what carries indigo to violet.
GRAD_FROM = (148, 162, 255)
GRAD_TO = (155, 119, 255)

# The checkmark's share of the tile it sits on. Kept identical for the
# full-bleed iOS art, so the glyph reads at the same weight on every platform.
CHECK_FRAC = 226 / 416


def diagonal_gradient(size: int) -> Image.Image:
    """A linear gradient along the top-left -> bottom-right diagonal."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            # Projection onto the diagonal, normalised to 0..1.
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(GRAD_FROM, GRAD_TO)
            )
    return img


# Whiteness thresholds on the darkest of R/G/B. The gradient itself never rises
# above ~166 there, but it carries faint dither up to ~200, so the ramp starts
# above that. Taking the mask as a *ramp* rather than a threshold is what
# preserves the original's antialiased edge - the tile is fully opaque, so the
# source alpha channel carries no edge information at all.
_WHITE_FLOOR = 200

# The glyph's own antialiasing lives between the two, so the bounding box is
# measured on solid pixels only. Measuring it on the ramp instead let a few
# stray dither pixels stretch the box and push the checkmark off centre.
_WHITE_SOLID = 240
_BBOX_PAD = 3


def check_mask() -> Image.Image:
    """The checkmark from the original, as a soft alpha mask on its own bbox."""
    r, g, b, a = Image.open(SOURCE).convert("RGBA").split()
    darkest = ImageChops.darker(ImageChops.darker(r, g), b)
    mask = darkest.point(
        lambda v: 0 if v <= _WHITE_FLOOR else round(255 * (v - _WHITE_FLOOR) / (255 - _WHITE_FLOOR))
    )

    # The tile's own antialiased outer edge stores near-white RGB under partial
    # alpha, which whiteness alone reads as checkmark - it is what put a ghost
    # ring around the glyph and stretched the bbox to the whole tile. The
    # checkmark's edge sits *inside* the tile and stays fully opaque, so gating
    # on full opacity drops the rim without touching the glyph's antialiasing.
    opaque = a.point(lambda v: 255 if v >= 250 else 0)
    mask = ImageChops.multiply(mask, opaque)

    solid = ImageChops.multiply(
        darkest.point(lambda v: 255 if v > _WHITE_SOLID else 0), opaque
    )
    x0, y0, x1, y1 = solid.getbbox()
    return mask.crop((
        max(0, x0 - _BBOX_PAD),
        max(0, y0 - _BBOX_PAD),
        min(mask.width, x1 + _BBOX_PAD),
        min(mask.height, y1 + _BBOX_PAD),
    ))


def paste_check(canvas: Image.Image, box_width: int) -> None:
    """Centre the checkmark on `canvas`, `box_width` wide, preserving aspect."""
    mask = check_mask()
    target = (box_width, round(mask.height * box_width / mask.width))

    white = Image.new("RGBA", target, (255, 255, 255, 255))
    white.putalpha(mask.resize(target, Image.LANCZOS))

    x = (canvas.width - target[0]) // 2
    y = (canvas.height - target[1]) // 2
    canvas.alpha_composite(white, (x, y))


def rounded_tile(size: int, inset_frac: float, radius_frac: float) -> Image.Image:
    """The gradient clipped to a rounded rectangle, on transparency."""
    inset = round(size * inset_frac)
    tile = size - 2 * inset
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - inset - 1, size - inset - 1],
        radius=round(tile * radius_frac),
        fill=255,
    )
    out = diagonal_gradient(size).convert("RGBA")
    out.putalpha(mask)
    return out


def main() -> None:
    ASSETS.mkdir(exist_ok=True)

    # 1. The tile, on transparency.
    tile = rounded_tile(SIZE, TILE_INSET, TILE_RADIUS)
    paste_check(tile, round(SIZE * (1 - 2 * TILE_INSET) * CHECK_FRAC))
    tile.save(ASSETS / "icon.png")

    # 2. iOS: full bleed and fully opaque. iOS applies its own squircle mask, so
    #    shipping our rounded tile would show a tile inside a tile, and an alpha
    #    channel is rejected outright by App Store validation.
    ios = diagonal_gradient(SIZE).convert("RGBA")
    paste_check(ios, round(SIZE * CHECK_FRAC))
    ios.convert("RGB").save(ASSETS / "icon_ios.png")

    # 3. Android adaptive foreground. The outer third of an adaptive icon can be
    #    cropped by the launcher's mask, so the glyph sits well inside it.
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    paste_check(fg, round(SIZE * 0.42))
    fg.save(ASSETS / "icon_adaptive_fg.png")

    # 4. Tray. A notification-area icon is drawn at 16px, where the tile's 9.4%
    #    padding costs about a third of the glyph's width for nothing - the
    #    tray already spaces its icons. So the tray art uses a tighter inset
    #    and a proportionally tighter corner radius.
    tray = rounded_tile(SIZE, TRAY_INSET, TILE_RADIUS * (1 - 2 * TILE_INSET) / (1 - 2 * TRAY_INSET))
    paste_check(tray, round(SIZE * (1 - 2 * TRAY_INSET) * CHECK_FRAC))
    tray.resize((32, 32), Image.LANCZOS).save(ASSETS / "tray_icon.png")
    # Windows wants every size present in the .ico itself; left to scale a
    # single large frame down, the shell produces a visibly muddy 16px icon.
    tray.save(
        ASSETS / "tray_icon.ico",
        sizes=[(s, s) for s in (16, 20, 24, 32, 48, 64, 128, 256)],
    )

    print("wrote:", *(f.name for f in sorted(ASSETS.glob("*.png"))))


if __name__ == "__main__":
    main()
