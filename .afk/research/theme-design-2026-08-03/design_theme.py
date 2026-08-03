#!/usr/bin/env python3
"""
design_theme.py — construct and MEASURE a terminal palette for Umber.

Why this exists as a tool rather than a hand-picked hex list: every claim a theme
makes about itself ("legible", "colour-blind safe", "the bright ring is distinct")
is a number, and a number nobody computed is a taste claim wearing a lab coat.
This file computes them.

Implements from scratch (no colour libraries, so every step is auditable):
  * sRGB <-> linear <-> OKLab/OKLCH            — Ottosson 2020
  * gamut mapping by binary-search chroma reduction, per CSS Color 4 §13
  * WCAG 2.1 relative luminance + contrast ratio
  * APCA 0.98G-4g lightness contrast (Lc)      — the model that does NOT
    overstate contrast on dark backgrounds, which is the whole regime here
  * dichromacy simulation (Vienot/Brettel/Mollon 1999) for protanopia and
    deuteranopia, then dE-OK between the simulated pair

Run: python3 design_theme.py
Emits: a Swift-ready hex table + a full measurement report to stdout.
"""

import numpy as np

# ---------------------------------------------------------------- sRGB / OKLab

def srgb_to_linear(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def linear_to_srgb(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.clip(c, 0, None), 1 / 2.4) - 0.055)

# Ottosson's matrices (bottosson.github.io/posts/oklab/)
M1 = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005],
])
M2 = np.array([
    [0.2104542553,  0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050,  0.4505937099],
    [0.0259040371,  0.7827717662, -0.8086757660],
])
M1i, M2i = np.linalg.inv(M1), np.linalg.inv(M2)

def linear_to_oklab(rgb):
    lms = M1 @ np.asarray(rgb, dtype=float)
    return M2 @ np.cbrt(lms)

def oklab_to_linear(lab):
    lms = M2i @ np.asarray(lab, dtype=float)
    return M1i @ (lms ** 3)

def oklch_to_oklab(L, C, H):
    h = np.deg2rad(H)
    return np.array([L, C * np.cos(h), C * np.sin(h)])

def oklab_to_oklch(lab):
    L, a, b = lab
    return L, float(np.hypot(a, b)), float(np.rad2deg(np.arctan2(b, a)) % 360)

def in_gamut(lin, eps=1e-4):
    return bool(np.all(lin >= -eps) and np.all(lin <= 1 + eps))

def oklch_to_hex(L, C, H):
    """Gamut-map by reducing chroma only (CSS Color 4 §13): preserves hue and
    lightness, which is exactly the invariant a constant-lightness ring needs.
    Naive per-channel RGB clipping shifts hue by up to ~22 degrees."""
    lo, hi = 0.0, C
    if in_gamut(oklab_to_linear(oklch_to_oklab(L, C, H))):
        lo = C
    else:
        for _ in range(48):
            mid = (lo + hi) / 2
            if in_gamut(oklab_to_linear(oklch_to_oklab(L, mid, H))):
                lo = mid
            else:
                hi = mid
    lin = np.clip(oklab_to_linear(oklch_to_oklab(L, lo, H)), 0, 1)
    srgb = np.clip(linear_to_srgb(lin), 0, 1)
    r, g, b = (int(round(v * 255)) for v in srgb)
    return "#%02X%02X%02X" % (r, g, b), lo

def hex_to_srgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])

def hex_to_oklch(h):
    return oklab_to_oklch(linear_to_oklab(srgb_to_linear(hex_to_srgb(h))))

# --------------------------------------------------------------- WCAG 2.1

def wcag_Y(h):
    lin = srgb_to_linear(hex_to_srgb(h))
    return float(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2])

def wcag_ratio(a, b):
    ya, yb = wcag_Y(a), wcag_Y(b)
    hi, lo = max(ya, yb), min(ya, yb)
    return (hi + 0.05) / (lo + 0.05)

# --------------------------------------------------------------- APCA 0.98G-4g
# git.apcacontrast.com/documentation/APCAeasyIntro.html
# Reported as absolute Lc. Thresholds: 90 preferred body, 75 min body,
# 60 min readable non-body, 45 large/headline, 30 floor, 15 invisible.

_MAIN_TRC, _BLK_THRS, _BLK_CLMP = 2.4, 0.022, 1.414
_NORM_BG, _NORM_TXT, _REV_TXT, _REV_BG = 0.56, 0.57, 0.62, 0.65
_SCALE, _OFFSET, _LO_CLIP, _DELTA_Y_MIN = 1.14, 0.027, 0.1, 0.0005

def _apca_Y(h):
    s = hex_to_srgb(h)
    y = 0.2126729 * s[0] ** _MAIN_TRC + 0.7151522 * s[1] ** _MAIN_TRC + 0.0721750 * s[2] ** _MAIN_TRC
    return y + (_BLK_THRS - y) ** _BLK_CLMP if y < _BLK_THRS else y

def apca_lc(text_hex, bg_hex):
    ytxt, ybg = _apca_Y(text_hex), _apca_Y(bg_hex)
    if abs(ybg - ytxt) < _DELTA_Y_MIN:
        return 0.0
    if ybg > ytxt:                                    # dark text on light bg
        sapc = (ybg ** _NORM_BG - ytxt ** _NORM_TXT) * _SCALE
        out = 0.0 if sapc < _LO_CLIP else sapc - _OFFSET
    else:                                             # light text on dark bg
        sapc = (ybg ** _REV_BG - ytxt ** _REV_TXT) * _SCALE
        out = 0.0 if sapc > -_LO_CLIP else sapc + _OFFSET
    return abs(out * 100)

# ------------------------------------------------- dichromacy (Vienot 1999)

_RGB2LMS = np.array([
    [17.8824,    43.5161,   4.11935],
    [ 3.45565,   27.1554,   3.86714],
    [ 0.0299566,  0.184309, 1.46709],
])
_LMS2RGB = np.linalg.inv(_RGB2LMS)
_PROTAN = np.array([[0, 2.02344, -2.52581], [0, 1, 0], [0, 0, 1]])
_DEUTAN = np.array([[1, 0, 0], [0.494207, 0, 1.24827], [0, 0, 1]])

def simulate(h, kind):
    lin = srgb_to_linear(hex_to_srgb(h))
    lms = _RGB2LMS @ lin
    lms = (_PROTAN if kind == "protan" else _DEUTAN) @ lms
    out = np.clip(_LMS2RGB @ lms, 0, 1)
    r, g, b = (int(round(v * 255)) for v in np.clip(linear_to_srgb(out), 0, 1))
    return "#%02X%02X%02X" % (r, g, b)

def deltaE_ok(h1, h2):
    a = linear_to_oklab(srgb_to_linear(hex_to_srgb(h1)))
    b = linear_to_oklab(srgb_to_linear(hex_to_srgb(h2)))
    return float(np.linalg.norm(a - b))

# =============================================================== THE DESIGN
# Two lightness rings, deliberately separated, so "bright" is a measurable step
# and not a synonym. Hues are chosen for CVD survival first and mood second:
# red is pushed to vermilion and green to bluish-green (Okabe-Ito's substitution)
# so the red/green axis that git diff rides on keeps a lightness AND hue-angle
# gap under both protanopia and deuteranopia.

BG_H, BG_C = 56.0, 0.014          # warm umber-black: hue of raw umber earth, chroma
                                  # low enough to read "warm neutral", not "brown"
NORMAL_L, BRIGHT_L = 0.715, 0.845

#            name          hue    C_norm  C_brt   L_norm         L_bright
SPEC = [
    ("black",             56.0,  0.016,  0.014,  0.300,          0.430),
    ("red",               27.0,  0.150,  0.130,  NORMAL_L-0.020, BRIGHT_L-0.025),
    ("green",            158.0,  0.115,  0.110,  NORMAL_L+0.030, BRIGHT_L+0.020),
    ("yellow",            80.0,  0.135,  0.130,  NORMAL_L+0.015, BRIGHT_L+0.010),
    ("blue",             252.0,  0.115,  0.105,  NORMAL_L-0.005, BRIGHT_L-0.010),
    ("magenta",          330.0,  0.135,  0.120,  NORMAL_L,       BRIGHT_L-0.005),
    ("cyan",             203.0,  0.100,  0.095,  NORMAL_L+0.020, BRIGHT_L+0.015),
    ("white",             70.0,  0.012,  0.008,  0.855,          0.955),
]

def build():
    bg, _ = oklch_to_hex(0.196, BG_C, BG_H)
    fg, _ = oklch_to_hex(0.902, 0.013, 78.0)
    cursor, _ = oklch_to_hex(0.760, 0.150, 52.0)     # warm umber-orange caret
    sel, _ = oklch_to_hex(0.330, 0.040, 56.0)        # selection: a warm lift of bg
    ansi, meta = [], []
    for name, hue, cn, cb, ln, lb in SPEC:
        hn, actual_cn = oklch_to_hex(ln, cn, hue)
        ansi.append((name, hn))
        meta.append((name, ln, cn, actual_cn, hue))
    for name, hue, cn, cb, ln, lb in SPEC:
        hb, actual_cb = oklch_to_hex(lb, cb, hue)
        ansi.append(("bright " + name, hb))
        meta.append(("bright " + name, lb, cb, actual_cb, hue))
    return bg, fg, cursor, sel, ansi, meta

def report():
    bg, fg, cursor, sel, ansi, meta = build()
    print("=" * 78)
    print("UMBER — measured palette report")
    print("=" * 78)
    bgL, bgC, bgH = hex_to_oklch(bg)
    print(f"\nbackground {bg}  OKLCH({bgL:.3f} {bgC:.3f} {bgH:.1f})  WCAG-Y {wcag_Y(bg):.5f}")
    print(f"  lightChromeCutoff is 0.179 (Config.swift) -> chrome resolves "
          f"{'DARK  (correct)' if wcag_Y(bg) <= 0.179 else 'LIGHT (WRONG)'}")
    for label, h in (("foreground", fg), ("cursor", cursor), ("selection bg", sel)):
        L, C, H = hex_to_oklch(h)
        print(f"{label:>12} {h}  OKLCH({L:.3f} {C:.3f} {H:5.1f})  "
              f"WCAG {wcag_ratio(h, bg):5.2f}:1   APCA Lc {apca_lc(h, bg):5.1f}")

    print("\n" + "-" * 78)
    print("ANSI 0-15 vs background — APCA Lc floor for readable non-body text is 60")
    print("-" * 78)
    print(f"{'idx':>3} {'name':<15} {'hex':<9} {'OKLCH':<22} {'WCAG':>7} {'APCA':>6}  verdict")
    worst = (999, "")
    for i, (name, h) in enumerate(ansi):
        L, C, H = hex_to_oklch(h)
        lc, wr = apca_lc(h, bg), wcag_ratio(h, bg)
        ok = "OK" if lc >= 60 else ("weak" if lc >= 45 else "FAIL")
        if i != 0 and lc < worst[0]:
            worst = (lc, f"{i} {name}")
        print(f"{i:>3} {name:<15} {h:<9} ({L:.3f} {C:.3f} {H:5.1f})  "
              f"{wr:6.2f}:1 {lc:6.1f}  {ok}")
    print(f"\n  worst non-index-0 slot: {worst[1]} at Lc {worst[0]:.1f}")
    print(f"  index 0 (ANSI black) is Lc {apca_lc(ansi[0][1], bg):.1f} on purpose — it is a")
    print("  SURFACE colour, never body text; it must be visible against bg, not readable.")

    print("\n" + "-" * 78)
    print("normal vs bright ring separation — dE-OK; >=0.10 is unambiguous")
    print("-" * 78)
    for i in range(8):
        n, b = ansi[i][1], ansi[i + 8][1]
        dL = hex_to_oklch(b)[0] - hex_to_oklch(n)[0]
        de = deltaE_ok(n, b)
        print(f"  {ansi[i][0]:<8} {n} -> {b}   dL {dL:+.3f}  dE-OK {de:.3f}  "
              f"{'OK' if de >= 0.10 else 'TOO CLOSE'}")

    print("\n" + "-" * 78)
    print("colour-blind safety — the pairs a terminal actually depends on")
    print("-" * 78)
    pairs = [(1, 2, "red/green — git diff -/+, error vs success"),
             (9, 10, "bright red/green — same, bold"),
             (1, 3, "red/yellow — error vs warning"),
             (2, 3, "green/yellow"),
             (3, 11, "yellow/bright yellow"),
             (1, 9, "red/bright red — the Solarized failure"),
             (2, 6, "green/cyan"),
             (4, 5, "blue/magenta"),
             (8, 0, "bright black/black — comment vs surface")]
    for a, b, why in pairs:
        ha, hb = ansi[a][1], ansi[b][1]
        row = [f"  {a:>2}/{b:<2} {why:<44}"]
        for kind in ("normal", "protan", "deutan"):
            sa = ha if kind == "normal" else simulate(ha, kind)
            sb = hb if kind == "normal" else simulate(hb, kind)
            row.append(f"{kind[:6]} {deltaE_ok(sa, sb):.3f}")
        print("  ".join(row))
    print("\n  dE-OK >= 0.10 reads as clearly different; 0.05-0.10 is marginal;")
    print("  < 0.05 is a collision. Every row above must clear 0.10 in ALL THREE")
    print("  columns for the palette to be safe for git output.")

    print("\n" + "-" * 78)
    print("SWIFT — paste-ready")
    print("-" * 78)
    print(f'        background: NSColor.fromHex("{bg}")!,')
    print(f'        foreground: NSColor.fromHex("{fg}")!,')
    print(f'        cursor: NSColor.fromHex("{cursor}")!,')
    print("        ansi: [")
    for r in range(4):
        row = ", ".join(f'"{ansi[r * 4 + c][1]}"' for c in range(4))
        print(f"            {row},")
    print("        ].map { NSColor.fromHex($0)! }")
    print(f'\n  selection background (not yet a Theme field): "{sel}"')
    return bg, fg, cursor, sel, ansi

if __name__ == "__main__":
    report()
