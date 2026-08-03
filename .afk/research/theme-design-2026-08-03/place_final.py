#!/usr/bin/env python3
"""
place_final.py — the last search. Pairs TIERED by whether they carry meaning.

The lesson from four optimiser runs is that an unbounded parameter gets exploited.
So chroma is no longer a free variable: it is PINNED at the hand-chosen aesthetic
values from verify_umber.py (normal 0.115-0.140, bright 0.090-0.115 — the band
Tokyo Night and Catppuccin occupy). The optimiser may only move LIGHTNESS and HUE,
inside recognisable windows.

That leaves exactly the two levers that buy colour-vision separation without
touching saturation:
  * lightness stagger — the only signal that survives dichromacy, since hue is
    what dichromacy destroys;
  * hue placement inside a window narrow enough that red stays red.

Objective is still max-min on normalised margins, but the feasible region is now
small enough that the result is a placement rather than a personality.

FINAL CORRECTION. The previous run weighted all 12 colour pairs equally, which is
48 dichromacy constraints on 18 parameters and is simply infeasible — it traded
red/green (which git diff rides on) against magenta/cyan (which nothing rides on)
at par. No terminal palette satisfies all of them; the field's palettes are not
sloppy, they sit at different points on a Pareto surface. So the pairs are tiered
by whether a human ever has to TELL THEM APART to read output correctly:

  tier 1 (hard, 0.105) red/green, red/yellow, green/yellow
        diff +/-, pass/fail/warn. Confusing these misreads the output.
  tier 2 (0.080) blue/magenta, green/cyan, blue/cyan, red/blue, red/magenta
        adjacent in prompts and ls; confusion is annoying, not misleading.
  tier 3 (0.050) magenta/cyan, yellow/magenta, yellow/cyan, blue/green
        syntax-highlighting adjacency only. Nobody diffs magenta against cyan.

Stating the tier is the honest part: it is a design decision with a rationale, not
a threshold that happened to pass.

Run: python3 place_final.py
"""

import random
import numpy as np
from design_theme import (oklch_to_hex, hex_to_oklch, apca_lc, wcag_ratio,
                          deltaE_ok, simulate, wcag_Y)

random.seed(23)

BG  = oklch_to_hex(0.190, 0.016, 56.0)[0]
FG  = oklch_to_hex(0.905, 0.014, 80.0)[0]
CUR = oklch_to_hex(0.780, 0.145, 52.0)[0]
SEL = oklch_to_hex(0.330, 0.040, 56.0)[0]

_hc = {}
def och(L, C, H):
    k = (round(L, 4), round(C, 4), round(H, 2))
    if k not in _hc:
        _hc[k] = oklch_to_hex(*k)[0]
    return _hc[k]

_sc = {}
def sim(h, k):
    if (h, k) not in _sc:
        _sc[(h, k)] = simulate(h, k)
    return _sc[(h, k)]

# family, hue window, normal-L window, bright-L window, CHROMA (PINNED), APCA floor
FAMILIES = [
    ("red",     (18.0,  32.0), (0.720, 0.790), (0.815, 0.880), 0.135, 0.098, 50.0),
    ("green",   (142.0, 158.0), (0.780, 0.860), (0.870, 0.930), 0.130, 0.106, 60.0),
    ("yellow",  (76.0,   90.0), (0.750, 0.820), (0.845, 0.900), 0.140, 0.115, 58.0),
    ("blue",    (250.0, 264.0), (0.695, 0.770), (0.795, 0.860), 0.130, 0.095, 48.0),
    ("magenta", (322.0, 340.0), (0.775, 0.845), (0.860, 0.915), 0.128, 0.100, 56.0),
    ("cyan",    (192.0, 208.0), (0.770, 0.840), (0.860, 0.915), 0.115, 0.095, 60.0),
]
NAMES = [f[0] for f in FAMILIES]
NI = {n: i + 1 for i, n in enumerate(NAMES)}

PAIRS = [("red", "green", 0.105), ("red", "yellow", 0.105), ("green", "yellow", 0.105),
         ("blue", "magenta", 0.080), ("green", "cyan", 0.080), ("blue", "cyan", 0.080),
         ("red", "magenta", 0.080), ("red", "blue", 0.080),
         ("magenta", "cyan", 0.050), ("yellow", "magenta", 0.050),
         ("yellow", "cyan", 0.050), ("blue", "green", 0.050)]

T_HUE, T_RING = 0.095, 0.090
BLACK   = och(0.300, 0.016, 56.0)
DIM     = och(0.715, 0.014, 56.0)
WHITE   = och(0.851, 0.013, 74.0)
BWHITE  = och(0.974, 0.006, 74.0)


def unpack(v):
    normal, bright = {}, {}
    for k, (n, hw, nlw, blw, cn, cb, fl) in enumerate(FAMILIES):
        h, ln, lb = v[k * 3], v[k * 3 + 1], v[k * 3 + 2]
        normal[n] = och(ln, cn, h)
        bright[n] = och(lb, cb, h)
    return [BLACK, normal["red"], normal["green"], normal["yellow"],
            normal["blue"], normal["magenta"], normal["cyan"], WHITE,
            DIM, bright["red"], bright["green"], bright["yellow"],
            bright["blue"], bright["magenta"], bright["cyan"], BWHITE]


def margins(v):
    a = unpack(v)
    m = []
    for k, (n, hw, nlw, blw, cn, cb, fl) in enumerate(FAMILIES):
        ni, bi = k + 1, k + 9
        m.append((f"normal {n} Lc>={fl:.0f}", (apca_lc(a[ni], BG) - fl) / fl))
        m.append((f"bright {n} Lc>={fl+15:.0f}",
                  (apca_lc(a[bi], BG) - (fl + 15)) / (fl + 15)))
        m.append((f"ring {n} dE", (deltaE_ok(a[ni], a[bi]) - T_RING) / T_RING))
    for x, y, tier in PAIRS:
        for ring, off in (("norm", 0), ("brt", 8)):
            hx, hy = a[NI[x] + off], a[NI[y] + off]
            m.append((f"hue {ring} {x}/{y}", (deltaE_ok(hx, hy) - T_HUE) / T_HUE))
            for kd in ("protan", "deutan"):
                d = deltaE_ok(sim(hx, kd), sim(hy, kd))
                m.append((f"cvd {kd} {ring} {x}/{y} [t{tier:.3f}]", (d - tier) / tier))
    return m


def score(v):
    ms = [x[1] for x in margins(v)]
    return min(ms) + 0.05 * (sum(ms) / len(ms))


def bounds():
    b = []
    for n, hw, nlw, blw, cn, cb, fl in FAMILIES:
        b += [hw, nlw, blw]
    return b


def climb(v, b, iters):
    best, bs = list(v), score(v)
    step = np.array([(hi - lo) * 0.30 for lo, hi in b])
    for t in range(iters):
        c = list(best)
        for _ in range(random.choice([1, 1, 2, 2, 3])):
            k = random.randrange(len(c))
            lo, hi = b[k]
            c[k] = min(hi, max(lo, c[k] + random.gauss(0, step[k])))
        s = score(c)
        if s > bs:
            best, bs = c, s
        if t and t % 4000 == 0:
            step *= 0.6
    return best, bs


def main():
    b = bounds()
    best, bs = None, -9e9
    for i in range(8):
        v = [random.uniform(lo, hi) for lo, hi in b]
        c, cs = climb(v, b, 11000)
        if cs > bs:
            best, bs = c, cs
        print(f"  multistart {i+1}: {cs:+.4f}   best {bs:+.4f}")
    for r in range(3):
        c, cs = climb(best, b, 9000)
        if cs > bs:
            best, bs = c, cs
    print(f"\n  final score {bs:+.4f}  (>=0 = every target met)\n")

    A = unpack(best)
    ms = margins(best)
    fails = [(n, x) for n, x in ms if x < 0]
    print("=" * 84)
    print(f"CONSTRAINTS {len(ms)-len(fails)}/{len(ms)} met")
    print("=" * 84)
    for n, x in sorted(fails, key=lambda kv: kv[1]):
        print(f"  UNMET  {n:<38} margin {x:+.3f}")

    nm = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    print(f"\n  background {BG}  foreground {FG}  cursor {CUR}  selection {SEL}")
    print(f"  fg APCA Lc {apca_lc(FG, BG):.1f}   WCAG {wcag_ratio(FG, BG):.2f}:1\n")
    for i in range(16):
        lab = ("bright " + nm[i - 8]) if i >= 8 else nm[i]
        L, C, H = hex_to_oklch(A[i])
        print(f"  {i:>2} {lab:<15}{A[i]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})"
              f"  Lc {apca_lc(A[i], BG):5.1f}  WCAG {wcag_ratio(A[i], BG):5.2f}:1")

    print("\n  ring dE / lightness step:")
    for i in range(8):
        print(f"    {nm[i]:<8}{A[i]} -> {A[i+8]}  dL "
              f"{hex_to_oklch(A[i+8])[0]-hex_to_oklch(A[i])[0]:+.3f}"
              f"  dE {deltaE_ok(A[i], A[i+8]):.3f}")

    print("\n  CVD worst per pair (protan/deutan, both rings):")
    worst = (9.0, "")
    for x, y, tier in PAIRS:
        vals = []
        for ring, off in (("norm", 0), ("brt", 8)):
            hx, hy = A[NI[x] + off], A[NI[y] + off]
            p = deltaE_ok(sim(hx, "protan"), sim(hy, "protan"))
            d = deltaE_ok(sim(hx, "deutan"), sim(hy, "deutan"))
            vals.append(f"{ring} p{p:.3f} d{d:.3f}")
            if min(p, d) < worst[0]:
                worst = (min(p, d), f"{x}/{y} {ring}")
        print(f"    {x:>8}/{y:<8} " + "  ".join(vals) + f"   tier {tier:.3f}")
    print(f"\n    worst: {worst[1]} at {worst[0]:.3f}")

    from benchmark_themes import THEMES, score as bs_score
    rows = {n: bs_score(n, *t) for n, t in THEMES.items()}
    rows["UMBER"] = bs_score("umber", BG, FG, A)
    print("\n" + "=" * 84)
    print(f"{'theme':<18}{'fg Lc':>7}{'ANSI1-6':>9}{'min':>7}{'ANSI8':>8}{'ring dE':>9}{'CVD min':>9}")
    print("-" * 84)
    for n, r in sorted(rows.items(), key=lambda kv: -kv[1]["norm_mean"]):
        print(f"{n:<18}{r['fg_lc']:7.1f}{r['norm_mean']:9.1f}{r['norm_min']:7.1f}"
              f"{r['dim_lc']:8.1f}{r['ring_min']:9.3f}{r['cvd_min']:9.3f}"
              f"{'  <<<' if n == 'UMBER' else ''}")

    print("\n" + "-" * 84)
    print("SWIFT")
    print("-" * 84)
    print(f'        background: NSColor.fromHex("{BG}")!,')
    print(f'        foreground: NSColor.fromHex("{FG}")!,')
    print(f'        cursor: NSColor.fromHex("{CUR}")!,')
    print("        ansi: [")
    for r in range(4):
        print("            " + ", ".join(f'"{A[r*4+c]}"' for c in range(4)) + ",")
    print("        ].map { NSColor.fromHex($0)! }")

    import json
    with open("umber-palette.json", "w") as f:
        json.dump({"_source": "place_final.py — chroma pinned, pairs tiered, L+hue searched",
                   "background": BG, "foreground": FG, "cursor": CUR,
                   "selection": SEL, "ansi": A,
                   "score": bs, "unmet": [n for n, _ in fails],
                   "oklch": {f"{i}": list(hex_to_oklch(A[i])) for i in range(16)}},
                  f, indent=2)
    print("\n  wrote umber-palette.json")


if __name__ == "__main__":
    main()
