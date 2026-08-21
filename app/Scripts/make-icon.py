#!/usr/bin/env python3
"""Generate the Umber app icon.

Design intent
-------------
"Umber" contains "ember". The icon is warm light in the dark: a near-black
squircle with the pigment showing up as a glowing ember-gradient mark, rather
than as a brown background. Brown backgrounds read as mud; ember reads as heat.

That also puts it in the right reference class — modern dark developer tools
(Warp, Cursor, Linear, Raycast) — instead of 2011 skeuomorphism. No lit-sphere
gradient, no gloss, no heavy drop shadow.

Everything is sized for the WORST case (16x16 in the menu bar / Finder list).
The squircle occupies 824/1024 (Apple's macOS icon grid) and the mark's stroke
is >=112px at 1024 scale so it survives to ~1.8px at 16x16.

Usage:
  python3 make-icon.py                        # build/icon/icon_1024.png
  python3 make-icon.py --variant caret        # pick a treatment
  python3 make-icon.py --all                  # render every variant
  python3 make-icon.py --icns                 # + Umber.icns via iconutil
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- parameters
S = 1024
SS = 4                    # supersample factor
TILE = 824                # squircle edge on the 1024 grid (Apple macOS metric)
SQUIRCLE_N = 5.4          # superellipse exponent; ~5.4 matches Apple's corner

VARIANT_DEFAULT = "path"

# The icon is a small window of the app: these are the app's OWN colours.
# Background is the afk-dark theme background and the mark's mid stop is the
# real cursor colour -- both from Sources/Umber/Config.swift. Keep them in sync;
# the cool slate also makes the warm mark read hotter, and unlike a near-black
# tile it stays visible against a black Dock.
BG_TOP = (0x15, 0x1B, 0x24)
BG_BOTTOM = (0x0D, 0x11, 0x17)      # Config.swift afkDark.background

# the ember ramp — this is where "umber" actually lives
EMBER = [(0.0, (0xFF, 0xCB, 0xA4)), (0.46, (0xE6, 0x7E, 0x4C)), (1.0, (0xAE, 0x44, 0x1C))]
#                                    ^ Config.swift afkDark.cursor (#E67E4C)
# inverse colourway paints the tile with the ember and knocks the mark out dark
INK = (0x16, 0x10, 0x0C)

STROKE = 116              # mark stroke @1024 -> ~1.8px @16
BLOOM = 0.62              # ember bloom strength behind the mark
OPTICAL_LIFT = 0.010

# ---------------------------------------------------------- path mark colours
# Blue/cyan (discovery) → amber (embodiment).  The transition is COMPRESSED
# into a narrow band at the inflection point (t≈0.60-0.70) — no muddy grey-
# brown middle ground.  Blue holds through most of the descent; amber emerges
# decisively after the compression.
PATH_RAMP = [
    (0.00, (0x32, 0xA0, 0xC6)),   # steel-teal: the descent begins
    (0.40, (0x2C, 0x78, 0xA2)),   # deeper teal: hold blue through descent
    (0.60, (0x3E, 0x56, 0x72)),   # blue-grey: compression approach — cool, not brown
    (0.70, (0x9A, 0x64, 0x3C)),   # direct amber emergence — compressed transition
    (0.82, (0xE6, 0x7E, 0x4C)),   # Config.swift cursor — full ember
    (1.00, (0xFF, 0xCB, 0xA4)),   # bright peach: embodiment
]
PATH_BLOOM_COOL = (0x30, 0x9E, 0xC4)
PATH_BLOOM_WARM = (0xFF, 0x8A, 0x2B)


# ------------------------------------------------------------------ geometry
def squircle_mask(size: int, n: float) -> Image.Image:
    m = Image.new("L", (size, size), 0)
    px = m.load()
    r = size / 2.0
    for y in range(size):
        ny = abs((y + 0.5 - r) / r) ** n
        if ny > 1.0:
            continue
        half = (1.0 - ny) ** (1.0 / n) * r
        for x in range(max(0, int(r - half)), min(size, int(math.ceil(r + half)))):
            px[x, y] = 255
    return m


def gradient(size: int, stops: list) -> Image.Image:
    """Vertical multi-stop gradient."""
    g = Image.new("RGB", (1, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        t = y / max(1, size - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                k = (t - p0) / max(1e-6, p1 - p0)
                d.point((0, y), fill=tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)))
                break
        else:
            d.point((0, y), fill=stops[-1][1])
    return g.resize((size, size), Image.BILINEAR)


def diagonal_gradient(w: int, h: int, stops: list) -> Image.Image:
    """45-degree multi-stop ramp sized to a specific box."""
    g = Image.new("RGB", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x / max(1, w - 1) * 0.42) + (y / max(1, h - 1) * 0.58)
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]
                p1, c1 = stops[i + 1]
                if p0 <= t <= p1:
                    k = (t - p0) / max(1e-6, p1 - p0)
                    px[x, y] = tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
                    break
            else:
                px[x, y] = stops[-1][1]
    return g


def ember_over(tile: int, glyph: Image.Image, stops: list) -> Image.Image:
    """Ember ramp fitted to the glyph's ink bounds, not the tile."""
    bb = glyph.getbbox()
    layer = Image.new("RGB", (tile, tile), stops[-1][1])
    if bb:
        layer.paste(diagonal_gradient(bb[2] - bb[0], bb[3] - bb[1], stops), (bb[0], bb[1]))
    return layer.convert("RGBA")


def _unit(vx: float, vy: float) -> tuple:
    m = math.hypot(vx, vy) or 1.0
    return vx / m, vy / m


def mitred_chevron(d: ImageDraw.ImageDraw, p0, p1, p2, t: float, fill) -> None:
    """A chevron drawn as ONE filled polygon with a true mitre at the apex.

    Round caps read soft and generic (and made the first attempt look like a
    play button); flat ends with a mitred vertex read precise and technical.
    """
    (x0, y0), (x1, y1), (x2, y2) = p0, p1, p2
    dax, day = _unit(x1 - x0, y1 - y0)
    dbx, dby = _unit(x2 - x1, y2 - y1)
    nax, nay = -day, dax          # left normal of segment A
    nbx, nby = -dby, dbx          # left normal of segment B
    mx, my = _unit(nax + nbx, nay + nby)
    denom = max(0.35, mx * nax + my * nay)   # clamp: avoid a spike at sharp angles
    ml = (t / 2) / denom
    h = t / 2
    outer = [(x0 + nax * h, y0 + nay * h), (x1 + mx * ml, y1 + my * ml), (x2 + nbx * h, y2 + nby * h)]
    inner = [(x2 - nbx * h, y2 - nby * h), (x1 - mx * ml, y1 - my * ml), (x0 - nax * h, y0 - nay * h)]
    d.polygon(outer + inner, fill=fill)


# ---------------------------------------------------------- path mark (v3)
# 80% organic curve, 20% technical tension.  Three joined cubic Bézier
# segments with C1 continuity (tangent direction continuous, curvature may
# jump at the joins).  The joins create two subtle moments where the
# curvature tightens: one where the descent steepens, one at the compression.
# Circle-based rendering for smooth, continuous edges; endpoints taper to
# near-zero for clean termination without bulbs or facets.

def _bz(a, b, c, d, t):
    u = 1.0 - t
    return u*u*u*a + 3*u*u*t*b + 3*u*t*t*c + t*t*t*d


def _lerp_color(stops, t):
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if p0 <= t <= p1:
            k = (t - p0) / max(1e-6, p1 - p0)
            return tuple(round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
    return stops[-1][1]


def _smooth(stops, t):
    """Piecewise smoothstep — smooth transitions, no overshoot."""
    t = max(0.0, min(1.0, t))
    for i in range(len(stops) - 1):
        t0, v0 = stops[i]
        t1, v1 = stops[i + 1]
        if t0 <= t <= t1:
            k = (t - t0) / max(1e-9, t1 - t0)
            k = k * k * (3 - 2 * k)
            return v0 + (v1 - v0) * k
    return stops[-1][1]


def _make_segs(entry, s1c1, s1c2, j1, j1_arm, s2c2, j2, j2_arm, s3c2, end):
    """Build 3 cubic Béziers with guaranteed C1 at the two joins.

    j1_arm / j2_arm control the curvature DISCONTINUITY: shorter arm relative
    to the approach arm = tighter curvature on the exit side of the join.
    """
    s1 = [entry, s1c1, s1c2, j1]
    dx, dy = j1[0] - s1c2[0], j1[1] - s1c2[1]
    m = math.hypot(dx, dy) or 1
    s2 = [j1, (j1[0] + j1_arm * dx / m, j1[1] + j1_arm * dy / m), s2c2, j2]
    dx, dy = j2[0] - s2c2[0], j2[1] - s2c2[1]
    m = math.hypot(dx, dy) or 1
    s3 = [j2, (j2[0] + j2_arm * dx / m, j2[1] + j2_arm * dy / m), s3c2, end]
    return [s1, s2, s3]


# -- presets ---------------------------------------------------------------
# Three variants exploring the organic/tension dial.  All share the same
# layout points; only the join arm lengths and width envelope differ.
#
# t is split evenly: seg 1 = [0, 0.33), seg 2 = [0.33, 0.67), seg 3 = [0.67, 1].
# Join 1 (t≈0.33): descent steepens.  Join 2 (t≈0.67): the compression.

_LAYOUT = dict(
    entry=(-0.33, -0.03), s1c1=(-0.25, -0.02), s1c2=(-0.20, 0.01),
    j1=(-0.14, 0.04), s2c2=(-0.04, 0.10),
    j2=(0.02, 0.105), s3c2=(0.18, -0.02), end=(0.32, -0.08),
)


def _preset_A():
    """'Subtle' — 85/15 organic/tension.  Gentler curvature changes."""
    return dict(
        segments=_make_segs(**_LAYOUT, j1_arm=0.065, j2_arm=0.045),
        widths=[(0, .10), (.06, .66), (.25, .72), (.50, .60),
                (.65, .30), (.74, .50), (.86, .76), (.95, .68), (1, .08)])


def _preset_B():
    """'Balance' — 80/20 organic/tension.  The target."""
    return dict(
        segments=_make_segs(**_LAYOUT, j1_arm=0.050, j2_arm=0.030),
        widths=[(0, .10), (.06, .66), (.25, .72), (.50, .58),
                (.65, .26), (.74, .48), (.86, .76), (.95, .68), (1, .08)])


def _preset_C():
    """'Taut' — 75/25 organic/tension.  Tighter curvature breaks."""
    return dict(
        segments=_make_segs(**_LAYOUT, j1_arm=0.038, j2_arm=0.020),
        widths=[(0, .10), (.06, .66), (.25, .72), (.50, .56),
                (.65, .22), (.74, .46), (.86, .76), (.95, .68), (1, .08)])


PATH_PRESETS = dict(A=_preset_A, B=_preset_B, C=_preset_C)
PATH_DEFAULT_PRESET = "B"


def _eval_path(t, segments):
    idx = min(int(t * 3), 2)
    u = t * 3 - idx
    s = segments[idx]
    return (_bz(s[0][0], s[1][0], s[2][0], s[3][0], u),
            _bz(s[0][1], s[1][1], s[2][1], s[3][1], u))


def draw_path_mark(tile, scale, preset_name=PATH_DEFAULT_PRESET):
    """Circle-based rendering for organic smoothness with tapered endpoints."""
    cfg = PATH_PRESETS[preset_name]()
    segs, wenv = cfg["segments"], cfg["widths"]
    st = STROKE * scale
    n = 800
    cx, cy = tile / 2.0, tile / 2.0 - tile * OPTICAL_LIFT

    img = Image.new("RGBA", (tile, tile), (0, 0, 0, 0))
    mask = Image.new("L", (tile, tile), 0)
    d_img, d_mask = ImageDraw.Draw(img), ImageDraw.Draw(mask)
    for i in range(n + 1):
        t = i / n
        px, py = _eval_path(t, segs)
        x, y = cx + px * tile, cy + py * tile
        r = st * _smooth(wenv, t) / 2.0
        if r < 0.5:
            continue
        color = _lerp_color(PATH_RAMP, t)
        box = [x - r, y - r, x + r, y + r]
        d_img.ellipse(box, fill=color + (255,))
        d_mask.ellipse(box, fill=255)
    return img, mask


# ---------------------------------------------------------------------- mark
def mark_mask(tile: int, variant: str, scale: int) -> Image.Image:
    """White-on-black mask of the glyph, centred on its measured ink bounds."""
    m = Image.new("L", (tile, tile), 0)
    d = ImageDraw.Draw(m)
    st = STROKE * scale
    cy = tile // 2

    if variant in ("caret", "inverse_caret"):
        w, h = int(268 * scale), int(430 * scale)
        x0 = (tile - w) // 2
        mitred_chevron(d, (x0, cy - h // 2), (x0 + w, cy), (x0, cy + h // 2), st, 255)

    elif variant == "block":
        w, h = int(300 * scale), int(430 * scale)
        d.rounded_rectangle([(tile - w) // 2, cy - h // 2, (tile + w) // 2, cy + h // 2],
                            radius=int(46 * scale), fill=255)

    elif variant in ("cursorline", "inverse_cursorline"):
        # caret + a text-cursor block sitting ON the baseline (not centred) —
        # a centred full-height bar reads as "skip to end", a baseline block reads
        # as a terminal cursor.
        cw, ch = int(210 * scale), int(330 * scale)
        blw, blh = int(150 * scale), int(190 * scale)
        gap = int(104 * scale)
        total = cw + gap + blw
        x0 = (tile - total) // 2
        mitred_chevron(d, (x0, cy - ch // 2), (x0 + cw, cy), (x0, cy + ch // 2), st, 255)
        bx, base = x0 + cw + gap, cy + ch // 2
        d.rounded_rectangle([bx, base - blh, bx + blw, base],
                            radius=int(26 * scale), fill=255)

    else:  # "prompt" / "inverse_prompt" -> the unambiguous  >_
        cw, ch = int(206 * scale), int(330 * scale)
        bw = int(224 * scale)
        gap = int(84 * scale)
        total = cw + gap + bw
        x0 = (tile - total) // 2
        mitred_chevron(d, (x0, cy - ch // 2), (x0 + cw, cy), (x0, cy + ch // 2), st, 255)
        bx, base = x0 + cw + gap, cy + ch // 2
        d.rounded_rectangle([bx, base - st, bx + bw, base],
                            radius=int(st * 0.34), fill=255)

    bbox = m.getbbox()
    if bbox:
        ink = m.crop(bbox)
        out = Image.new("L", (tile, tile), 0)
        out.paste(ink, ((tile - ink.width) // 2, (tile - ink.height) // 2 - int(tile * OPTICAL_LIFT)))
        m = out
    return m


# --------------------------------------------------------------------- build
def build(scale: int = SS, variant: str = VARIANT_DEFAULT) -> Image.Image:
    n, tile = S * scale, TILE * scale
    off = (n - tile) // 2
    inverse = variant.startswith("inverse")
    is_path = variant == "path" or variant.startswith("path_")

    shape = squircle_mask(tile, SQUIRCLE_N)

    if is_path:
        preset = variant.split("_")[1] if "_" in variant else PATH_DEFAULT_PRESET
        mark_rgba, glyph = draw_path_mark(tile, scale, preset)
        body = gradient(tile, [(0.0, BG_TOP), (1.0, BG_BOTTOM)]).convert("RGBA")

        # dual-tinted bloom: cool on the left, warm on the right
        bloom_mask = glyph.filter(ImageFilter.GaussianBlur(tile * 0.050)).point(
            lambda v: int(v * BLOOM)
        )
        # split the bloom at the midpoint for a cool→warm glow
        cool_layer = Image.new("RGBA", (tile, tile), PATH_BLOOM_COOL + (255,))
        warm_layer = Image.new("RGBA", (tile, tile), PATH_BLOOM_WARM + (255,))
        # gradient mask: 0 on the left (cool shows) → 255 on the right (warm shows)
        lr = Image.new("L", (tile, tile), 0)
        for x in range(tile):
            col = int(255 * x / max(1, tile - 1))
            ImageDraw.Draw(lr).line([(x, 0), (x, tile - 1)], fill=col)
        bloom_tint = Image.composite(warm_layer, cool_layer, lr)
        body = Image.composite(bloom_tint, body, bloom_mask)
        body.alpha_composite(mark_rgba)
    elif inverse:
        glyph = mark_mask(tile, variant, scale)
        body = ember_over(tile, squircle_mask(tile, SQUIRCLE_N), EMBER)
        # knock the mark out of the ember slab
        ink = Image.new("RGBA", (tile, tile), INK + (255,))
        body = Image.composite(ink, body, glyph)
    else:
        glyph = mark_mask(tile, variant, scale)
        body = gradient(tile, [(0.0, BG_TOP), (1.0, BG_BOTTOM)]).convert("RGBA")

        # ember bloom: the mark lights the surface around it
        bloom = glyph.filter(ImageFilter.GaussianBlur(tile * 0.045)).point(
            lambda v: int(v * BLOOM)
        )
        body = Image.composite(
            Image.new("RGBA", (tile, tile), (0xFF, 0x8A, 0x2B, 255)), body, bloom
        )
        body = Image.composite(ember_over(tile, glyph, EMBER), body, glyph)

    # a single hairline of warm light along the top edge — depth without gloss
    rim = Image.new("L", (tile, tile), 0)
    ImageDraw.Draw(rim).ellipse(
        [int(-0.30 * tile), int(-0.055 * tile), int(1.30 * tile), int(0.030 * tile)], fill=54
    )
    rim = rim.filter(ImageFilter.GaussianBlur(tile * 0.006))
    body = Image.composite(Image.new("RGBA", (tile, tile), (255, 226, 190, 255)), body, rim)

    body.putalpha(shape)

    canvas = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 64), (off, off + int(10 * scale)), shape)
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8 * scale)))
    canvas.alpha_composite(body, (off, off))
    return canvas.resize((S, S), Image.LANCZOS)


PATH_VARIANT_NAMES = tuple(f"path_{k}" for k in PATH_PRESETS)
VARIANTS = ("path",) + PATH_VARIANT_NAMES + (
    "prompt", "cursorline", "caret", "inverse_prompt", "inverse_cursorline")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default=VARIANT_DEFAULT, choices=VARIANTS)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--explore", action="store_true",
                    help="Render all path presets A-F for comparison")
    ap.add_argument("--icns", action="store_true")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    outdir = Path(a.out) if a.out else root / "build" / "icon"
    outdir.mkdir(parents=True, exist_ok=True)

    if a.explore:
        for k in PATH_PRESETS:
            v = f"path_{k}"
            build(variant=v).save(outdir / f"variant_{v}.png")
            print(f"wrote {outdir / f'variant_{v}.png'}")
        return 0

    if a.all:
        for v in VARIANTS:
            build(variant=v).save(outdir / f"variant_{v}.png")
            print(f"wrote {outdir / f'variant_{v}.png'}")
        return 0

    img = build(variant=a.variant)
    img.save(outdir / "icon_1024.png")
    print(f"wrote {outdir / 'icon_1024.png'}  (variant={a.variant})")

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
