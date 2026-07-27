#!/usr/bin/env python3
"""Generate the Umber app icon.

Design intent
-------------
"Umber" is an earth pigment, so the icon *is* the name: a warm burnt-umber
squircle carrying a cream shell prompt (`>_`).

Everything is sized for the WORST case (16x16 in the menu bar / Finder list),
not the best case (1024 in the App Store). The squircle occupies 824/1024 —
Apple's macOS icon grid — and the glyph strokes are >=105px at 1024 scale so
they survive to ~1.6px at 16x16. Anything thinner disappears.

Rendered at 4x and downsampled for antialiasing (PIL has no AA primitives).

Usage:
  python3 make-icon.py                 # writes build/icon/icon_1024.png
  python3 make-icon.py --preview       # + ASCII luminance previews
  python3 make-icon.py --icns          # + Umber.icns via iconutil
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- parameters
S = 1024                 # nominal canvas
SS = 4                   # supersample factor
TILE = 824               # squircle edge on the 1024 grid (Apple macOS metric)
SQUIRCLE_N = 5.4         # superellipse exponent; ~5 matches Apple's continuous corner

TOP = (0xB4, 0x77, 0x3F)      # raw umber, lit
BOTTOM = (0x2E, 0x19, 0x0C)   # burnt umber, deep — wide range keeps it rich, not milky
CREAM = (0xF7, 0xEC, 0xD9)    # prompt glyph

STROKE = 106             # glyph stroke weight @1024  -> ~1.7px @16
CHEV_W, CHEV_H = 178, 264
GAP = 60
BAR_W = 170
OPTICAL_LIFT = 0.012     # fraction of tile; mass reads low without it
VARIANT_DEFAULT = "prompt"   # ">_" — the only treatment that reads as a terminal;
                             # "cursor" renders as >I (a media-skip button) and
                             # "chevron" as a play button. Kept for regeneration only.


def squircle_mask(size: int, n: float) -> Image.Image:
    """Superellipse |x|^n + |y|^n = 1, rasterised as an L mask."""
    m = Image.new("L", (size, size), 0)
    px = m.load()
    r = size / 2.0
    for y in range(size):
        ny = abs((y + 0.5 - r) / r) ** n
        if ny > 1.0:
            continue
        # solve |x|^n = 1 - ny  ->  half-width of the filled span on this row
        half = (1.0 - ny) ** (1.0 / n) * r
        x0, x1 = int(r - half), int(math.ceil(r + half))
        for x in range(max(0, x0), min(size, x1)):
            px[x, y] = 255
    return m


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    g = Image.new("RGB", (1, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        t = y / max(1, size - 1)
        d.point((0, y), fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size), Image.BILINEAR)


def round_cap_line(d: ImageDraw.ImageDraw, p0, p1, width: int, fill) -> None:
    """A stroked segment with genuine round caps (PIL's joint= is unreliable)."""
    d.line([p0, p1], fill=fill, width=width)
    r = width // 2
    for (x, y) in (p0, p1):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def build(scale: int = SS, variant: str = VARIANT_DEFAULT) -> Image.Image:
    n = S * scale
    tile = TILE * scale
    off = (n - tile) // 2

    # --- body: gradient clipped to the squircle -----------------------------
    mask = squircle_mask(tile, SQUIRCLE_N)
    body = vertical_gradient(tile, TOP, BOTTOM)

    # broad top sheen (not a corner blob — that reads blotchy at large sizes)
    glow = Image.new("L", (tile, tile), 0)
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        [int(-0.34 * tile), int(-0.62 * tile), int(1.22 * tile), int(0.60 * tile)],
        fill=42,
    )
    glow = glow.filter(ImageFilter.GaussianBlur(tile * 0.14))
    body = Image.composite(Image.new("RGB", (tile, tile), (0xC9, 0x88, 0x50)), body, glow)

    # --- glyph: >_ ----------------------------------------------------------
    gl = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    st = STROKE * scale
    cy = int(tile * 0.485)                    # optical centre sits just above true centre

    if variant == "chevron":
        # a single, confident chevron — maximum stroke mass at 16px
        cw, ch = int(250 * scale), int(400 * scale)
        x0 = (tile - cw) // 2 - int(18 * scale)   # optical: apex pulls the eye right
        apex_x = x0 + cw
        round_cap_line(gd, (x0, cy - ch // 2), (apex_x, cy), st, CREAM)
        round_cap_line(gd, (apex_x, cy), (x0, cy + ch // 2), st, CREAM)

    elif variant == "cursor":
        # chevron + block cursor, both vertically centred -> balanced mass
        cw, ch = int(200 * scale), int(310 * scale)
        blw, blh = int(132 * scale), int(310 * scale)
        gap = int(104 * scale)
        group_w = cw + gap + blw
        x0 = (tile - group_w) // 2
        apex_x = x0 + cw
        round_cap_line(gd, (x0, cy - ch // 2), (apex_x, cy), st, CREAM)
        round_cap_line(gd, (apex_x, cy), (x0, cy + ch // 2), st, CREAM)
        bx = x0 + cw + gap
        gd.rounded_rectangle(
            [bx, cy - blh // 2, bx + blw, cy + blh // 2],
            radius=int(26 * scale), fill=CREAM,
        )

    else:  # "prompt"  ->  >_
        cw, ch, gap, bw = CHEV_W * scale, CHEV_H * scale, GAP * scale, BAR_W * scale
        group_w = cw + gap + bw
        x0 = (tile - group_w) // 2
        apex_x = x0 + cw
        top_y, bot_y = cy - ch // 2, cy + ch // 2
        round_cap_line(gd, (x0, top_y), (apex_x, cy), st, CREAM)
        round_cap_line(gd, (apex_x, cy), (x0, bot_y), st, CREAM)
        round_cap_line(gd, (x0 + cw + gap, bot_y), (x0 + cw + gap + bw, bot_y), st, CREAM)

    # Re-centre the glyph on its MEASURED ink bounds rather than trusting the
    # layout maths. Bounding-box centring alone reads low, so lift optically.
    body = body.convert("RGBA")
    bbox = gl.getbbox()
    if bbox:
        ink = gl.crop(bbox)
        dx = (tile - ink.width) // 2 - bbox[0]
        dy = (tile - ink.height) // 2 - bbox[1] - int(tile * OPTICAL_LIFT)
        shifted = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
        shifted.paste(ink, (bbox[0] + dx, bbox[1] + dy))
        gl = shifted
    body.alpha_composite(gl)

    # --- top inner edge highlight (the native "lit rim") --------------------
    rim = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(rim).ellipse(
        [-tile, -int(tile * 0.10), tile * 2, int(tile * 0.16)], fill=64
    )
    rim = rim.filter(ImageFilter.GaussianBlur(tile * 0.012))
    body = Image.composite(Image.new("RGBA", (tile, tile), (255, 245, 230, 255)), body, rim)

    body.putalpha(mask)

    # --- compose onto the full canvas with a soft contact shadow ------------
    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 72), (off, off + int(11 * scale)), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(9 * scale))
    canvas.alpha_composite(sh)
    canvas.alpha_composite(body, (off, off))

    return canvas.resize((S, S), Image.LANCZOS)


# ------------------------------------------------------------------ preview
RAMP = " .:-=+*#%@"


def ascii_preview(img: Image.Image, cols: int) -> str:
    """Luminance ramp over a checkerboard matte — shows what survives at size."""
    sm = img.resize((cols, cols), Image.LANCZOS).convert("RGBA")
    bg = Image.new("RGBA", sm.size, (0, 0, 0, 255))
    sm = Image.alpha_composite(bg, sm).convert("L")
    px = sm.load()
    out = []
    for y in range(cols):
        out.append("".join(RAMP[min(len(RAMP) - 1, px[x, y] * len(RAMP) // 256)] * 2
                           for x in range(cols)))
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--icns", action="store_true")
    ap.add_argument("--out", default=None)
    ap.add_argument("--variant", default=VARIANT_DEFAULT,
                    choices=("prompt", "cursor", "chevron"))
    a = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    outdir = Path(a.out) if a.out else root / "build" / "icon"
    outdir.mkdir(parents=True, exist_ok=True)

    img = build(variant=a.variant)
    master = outdir / "icon_1024.png"
    img.save(master)
    print(f"wrote {master}")

    if a.preview:
        for c in (16, 32, 64):
            print(f"\n--- {c}x{c} ---")
            print(ascii_preview(img, c))

    if a.icns:
        iconset = outdir / "Umber.iconset"
        iconset.mkdir(exist_ok=True)
        for sz in (16, 32, 128, 256, 512):
            img.resize((sz, sz), Image.LANCZOS).save(iconset / f"icon_{sz}x{sz}.png")
            img.resize((sz * 2, sz * 2), Image.LANCZOS).save(iconset / f"icon_{sz}x{sz}@2x.png")
        icns = outdir / "Umber.icns"
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
        print(f"wrote {icns}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
