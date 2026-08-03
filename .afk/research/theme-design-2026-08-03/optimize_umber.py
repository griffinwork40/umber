#!/usr/bin/env python3
"""
optimize_umber.py — search for the palette, don't guess it.

The hand-tuned first draft failed its own targets (normal ring Lc 46-59, a
deuteranopia red/green collision at dE 0.062). Rather than nudge hex by eye,
this states the targets as hard constraints and hill-climbs a parameter vector
until every one is met with margin.

Objective is MAX-MIN on normalised constraint margins: the score is the worst
constraint's margin, so the optimiser cannot buy a beautiful blue by sacrificing
the comment colour. Everything is measured by the same functions that judged the
field in benchmark_themes.py.

Hue ranges are bounded so "red" still looks red — a palette that optimises its
way to a teal ANSI 1 has solved the wrong problem.

Run: python3 optimize_umber.py
"""

import random
import numpy as np
from design_theme import (oklch_to_hex, hex_to_oklch, apca_lc, wcag_ratio,
                          deltaE_ok, simulate, wcag_Y)

random.seed(7)

# ----------------------------------------------------------------- targets
T_FG_LC        = 90.0   # APCA preferred body text
T_NORM_LC      = 62.0   # readable non-body floor is 60; ask for margin
T_BRIGHT_LC    = 78.0   # bright ring carries bold text; ask above min-body 75
T_DIM_LC       = 48.0   # ANSI 8 = comments. Floor 45. Whole field fails this.
T_SURFACE_LC   = 8.0    # ANSI 0 must be *visible* on bg, not readable
T_RING_DE      = 0.105  # normal -> bright must be unambiguous
T_CVD_DE       = 0.105  # every critical pair, under protanopia AND deuteranopia
T_HUE_DE       = 0.105  # adjacent hue families must not collide for normal vision

# background is the thesis, not a free variable: warm umber-black.
BG = oklch_to_hex(0.196, 0.014, 56.0)[0]

# family, hue range, normal-L range, bright-L range, chroma cap
FAMILIES = [
    ("red",     (18.0,  42.0), (0.66, 0.80), (0.79, 0.92), 0.19),
    ("green",   (138.0, 172.0), (0.70, 0.86), (0.82, 0.94), 0.17),
    ("yellow",  (68.0,  98.0), (0.72, 0.86), (0.83, 0.94), 0.19),
    ("blue",    (236.0, 268.0), (0.66, 0.82), (0.79, 0.92), 0.17),
    ("magenta", (312.0, 348.0), (0.66, 0.82), (0.79, 0.92), 0.19),
    ("cyan",    (186.0, 224.0), (0.70, 0.86), (0.82, 0.94), 0.15),
]

# the pairs a terminal's meaning actually rides on
CVD_PAIRS = [("red", "green"), ("red", "yellow"), ("green", "yellow"),
             ("blue", "magenta"), ("green", "cyan"), ("blue", "cyan"),
             ("red", "magenta")]


def unpack(v):
    """parameter vector -> (fg, ansi16, meta)"""
    i = 0
    fg = oklch_to_hex(v[i], 0.013, 78.0)[0]; i += 1
    surf_L, dim_L, w_L, bw_L = v[i], v[i + 1], v[i + 2], v[i + 3]; i += 4
    normal, bright, meta = {}, {}, {}
    for name, hr, lr, br, cc in FAMILIES:
        h, ln, cn, lb, cb = v[i], v[i + 1], v[i + 2], v[i + 3], v[i + 4]; i += 5
        normal[name] = oklch_to_hex(ln, cn, h)[0]
        bright[name] = oklch_to_hex(lb, cb, h)[0]
        meta[name] = (h, ln, cn, lb, cb)
    ansi = [
        oklch_to_hex(surf_L, 0.016, 56.0)[0],
        normal["red"], normal["green"], normal["yellow"],
        normal["blue"], normal["magenta"], normal["cyan"],
        oklch_to_hex(w_L, 0.012, 70.0)[0],
        oklch_to_hex(dim_L, 0.014, 56.0)[0],
        bright["red"], bright["green"], bright["yellow"],
        bright["blue"], bright["magenta"], bright["cyan"],
        oklch_to_hex(bw_L, 0.009, 70.0)[0],
    ]
    return fg, ansi, meta


def margins(v):
    """List of (name, normalised margin). Margin >= 0 means the target is met."""
    fg, a, meta = unpack(v)
    m = []
    m.append(("fg body text", (apca_lc(fg, BG) - T_FG_LC) / T_FG_LC))
    for idx, nm in ((1, "red"), (2, "green"), (3, "yellow"),
                    (4, "blue"), (5, "magenta"), (6, "cyan")):
        m.append((f"normal {nm} Lc", (apca_lc(a[idx], BG) - T_NORM_LC) / T_NORM_LC))
    for idx, nm in ((9, "red"), (10, "green"), (11, "yellow"),
                    (12, "blue"), (13, "magenta"), (14, "cyan")):
        m.append((f"bright {nm} Lc", (apca_lc(a[idx], BG) - T_BRIGHT_LC) / T_BRIGHT_LC))
    m.append(("ANSI7 white Lc", (apca_lc(a[7], BG) - T_BRIGHT_LC) / T_BRIGHT_LC))
    m.append(("ANSI15 br-white Lc", (apca_lc(a[15], BG) - 92.0) / 92.0))
    m.append(("ANSI8 comment Lc", (apca_lc(a[8], BG) - T_DIM_LC) / T_DIM_LC))
    m.append(("ANSI0 surface visible", (apca_lc(a[0], BG) - T_SURFACE_LC) / T_SURFACE_LC))
    for i in range(8):
        m.append((f"ring {i}/{i+8}", (deltaE_ok(a[i], a[i + 8]) - T_RING_DE) / T_RING_DE))
    NIDX = {"red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6}
    for x, y in CVD_PAIRS:
        hx, hy = a[NIDX[x]], a[NIDX[y]]
        m.append((f"hue {x}/{y} normal", (deltaE_ok(hx, hy) - T_HUE_DE) / T_HUE_DE))
        for k in ("protan", "deutan"):
            d = deltaE_ok(simulate(hx, k), simulate(hy, k))
            m.append((f"cvd {k} {x}/{y}", (d - T_CVD_DE) / T_CVD_DE))
        bx, by = a[NIDX[x] + 8], a[NIDX[y] + 8]
        for k in ("protan", "deutan"):
            d = deltaE_ok(simulate(bx, k), simulate(by, k))
            m.append((f"cvd {k} bright {x}/{y}", (d - T_CVD_DE) / T_CVD_DE))
    return m


def score(v):
    ms = [x[1] for x in margins(v)]
    # max-min, with a small mean term to break ties toward all-round quality
    return min(ms) + 0.02 * (sum(ms) / len(ms))


def bounds():
    b = [(0.88, 0.96)]                       # fg L
    b += [(0.26, 0.40), (0.52, 0.68), (0.82, 0.90), (0.93, 0.99)]  # surf, dim, white, br-white
    for name, hr, lr, br, cc in FAMILIES:
        b += [hr, lr, (0.04, cc), br, (0.04, cc)]
    return b


def seed():
    v = [0.92, 0.32, 0.60, 0.86, 0.96]
    for name, hr, lr, br, cc in FAMILIES:
        v += [sum(hr) / 2, sum(lr) / 2, cc * 0.7, sum(br) / 2, cc * 0.62]
    return v


def climb(v, b, iters=26000):
    best, bs = list(v), score(v)
    step = np.array([(hi - lo) * 0.22 for lo, hi in b])
    for t in range(iters):
        cand = list(best)
        k = random.randrange(len(cand))
        for _ in range(random.choice([1, 1, 1, 2, 3])):
            k = random.randrange(len(cand))
            lo, hi = b[k]
            cand[k] = min(hi, max(lo, cand[k] + random.gauss(0, step[k])))
        s = score(cand)
        if s > bs:
            best, bs = cand, s
        if t and t % 6500 == 0:
            step *= 0.45
    return best, bs


def main():
    b, v = bounds(), seed()
    print(f"seed score {score(v):+.4f}   (>= 0 means every target met)")
    best, bs = climb(v, b)
    # restart from best a few times with fresh noise to escape local optima
    for r in range(3):
        cand, cs = climb(best, b, iters=13000)
        if cs > bs:
            best, bs = cand, cs
        print(f"  restart {r + 1}: score {bs:+.4f}")
    print(f"\nfinal score {bs:+.4f}\n")

    fg, ansi, meta = unpack(best)
    cursor = oklch_to_hex(0.775, 0.150, 52.0)[0]
    sel = oklch_to_hex(0.335, 0.042, 56.0)[0]

    ms = margins(best)
    fails = [(n, x) for n, x in ms if x < 0]
    print("=" * 78)
    print(f"CONSTRAINTS: {len(ms) - len(fails)}/{len(ms)} met")
    print("=" * 78)
    if fails:
        for n, x in sorted(fails, key=lambda kv: kv[1]):
            print(f"  UNMET  {n:<34} margin {x:+.3f}")
    else:
        print("  all targets met")
    tight = sorted(ms, key=lambda kv: kv[1])[:6]
    print("\n  tightest satisfied constraints (the binding ones):")
    for n, x in tight:
        if x >= 0:
            print(f"    {n:<34} margin {x:+.3f}")

    print("\n" + "=" * 78)
    print("RESULT")
    print("=" * 78)
    print(f"  background  {BG}   OKLCH{tuple(round(x,3) for x in hex_to_oklch(BG))}"
          f"   WCAG-Y {wcag_Y(BG):.5f}  (< 0.179 -> dark chrome)")
    print(f"  foreground  {fg}   APCA Lc {apca_lc(fg, BG):5.1f}   WCAG {wcag_ratio(fg, BG):5.2f}:1")
    print(f"  cursor      {cursor}   APCA Lc {apca_lc(cursor, BG):5.1f}")
    print(f"  selection   {sel}")
    names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    print()
    for i in range(16):
        nm = ("bright " + names[i - 8]) if i >= 8 else names[i]
        L, C, H = hex_to_oklch(ansi[i])
        print(f"  {i:>2} {nm:<15}{ansi[i]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})"
              f"  Lc {apca_lc(ansi[i], BG):5.1f}  WCAG {wcag_ratio(ansi[i], BG):5.2f}:1")

    print("\n  CVD worst-case per critical pair (normal ring):")
    NIDX = {"red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6}
    for x, y in CVD_PAIRS:
        hx, hy = ansi[NIDX[x]], ansi[NIDX[y]]
        n = deltaE_ok(hx, hy)
        p = deltaE_ok(simulate(hx, "protan"), simulate(hy, "protan"))
        d = deltaE_ok(simulate(hx, "deutan"), simulate(hy, "deutan"))
        print(f"    {x:>8}/{y:<8} normal {n:.3f}  protan {p:.3f}  deutan {d:.3f}")

    print("\n" + "-" * 78)
    print("SWIFT")
    print("-" * 78)
    print(f'        background: NSColor.fromHex("{BG}")!,')
    print(f'        foreground: NSColor.fromHex("{fg}")!,')
    print(f'        cursor: NSColor.fromHex("{cursor}")!,')
    print("        ansi: [")
    for r in range(4):
        print("            " + ", ".join(f'"{ansi[r*4+c]}"' for c in range(4)) + ",")
    print("        ].map { NSColor.fromHex($0)! }")
    return BG, fg, cursor, ansi


if __name__ == "__main__":
    main()
