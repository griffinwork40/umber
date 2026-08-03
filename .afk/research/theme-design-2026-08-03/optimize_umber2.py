#!/usr/bin/env python3
"""
optimize_umber2.py — second pass, with targets derived from frontier.py.

What changed from v1, and why:

1. v1's `ANSI0 surface visible` constraint was measured in APCA and was
   MATHEMATICALLY UNSATISFIABLE — APCA's loClip returns exactly 0.0 below the
   invisibility threshold, and ANSI 0 is a surface a hair above the background
   by definition. A max-min objective with one infeasible term has no gradient
   anywhere, so the whole v1 run was unguided noise. ANSI 0 is now judged by
   dE-OK from the background, which is the right model for a non-text surface.

2. Per-family APCA floors replace the single uniform floor. frontier.py shows the
   ceiling at chroma>=0.10 is Lc 68 for red and 67 for blue but 97 for green:
   APCA weights luminance per channel (R .2127 G .7152 B .0722), so demanding one
   number from all six hues is a demand to desaturate red and blue to pastel.

3. Bright is parameterised as normal + dL with dL in [0.085, 0.14], so ring
   separation is STRUCTURAL rather than something the optimiser has to discover.
   v1 let the normal and bright L ranges overlap and duly collapsed the 3/11 pair.

4. The ring invariant is constant APCA Lc, NOT constant OKLCH L. The frontier
   makes constant-L and constant-readability mutually exclusive, and for a
   terminal readability is the property that matters. A consequence is that
   OKLCH L varies across the ring - which is also what buys the lightness spread
   that keeps red/green apart under deuteranopia.

Run: python3 optimize_umber2.py
"""

import random
import numpy as np
from design_theme import (oklch_to_hex, hex_to_oklch, apca_lc, wcag_ratio,
                          deltaE_ok, simulate, wcag_Y)

random.seed(11)

BG = oklch_to_hex(0.196, 0.014, 56.0)[0]

_hex_cache = {}
def och(L, C, H):
    k = (round(L, 4), round(C, 4), round(H, 2))
    v = _hex_cache.get(k)
    if v is None:
        v = oklch_to_hex(k[0], k[1], k[2])[0]
        _hex_cache[k] = v
    return v

_sim_cache = {}
def sim(h, k):
    key = (h, k)
    v = _sim_cache.get(key)
    if v is None:
        v = simulate(h, k)
        _sim_cache[key] = v
    return v

# family, hue range, normal-L range, chroma range, APCA floor (from frontier.py)
FAMILIES = [
    ("red",     (26.0,  52.0), (0.72, 0.86), (0.100, 0.175), 60.0),
    ("green",   (140.0, 172.0), (0.72, 0.88), (0.090, 0.190), 64.0),
    ("yellow",  (72.0,  100.0), (0.74, 0.90), (0.110, 0.180), 64.0),
    ("blue",    (234.0, 262.0), (0.72, 0.86), (0.090, 0.165), 60.0),
    ("magenta", (310.0, 344.0), (0.72, 0.88), (0.100, 0.185), 62.0),
    ("cyan",    (188.0, 218.0), (0.74, 0.88), (0.080, 0.145), 64.0),
]
NAMES = [f[0] for f in FAMILIES]

CVD_PAIRS = [("red", "green"), ("red", "yellow"), ("green", "yellow"),
             ("blue", "magenta"), ("green", "cyan"), ("blue", "cyan"),
             ("red", "magenta"), ("yellow", "cyan"), ("red", "blue")]

T_RING_DE, T_CVD_DE, T_HUE_DE = 0.105, 0.105, 0.105
T_BRIGHT_BONUS = 15.0     # bright slot must clear its family floor by this much
T_RING_SPREAD  = 14.0     # max Lc spread within a ring, so it reads as ONE ring


def unpack(v):
    i = 0
    fg   = och(v[i], 0.013, 78.0); i += 1
    surf = och(v[i], 0.016, 56.0); i += 1
    dim  = och(v[i], 0.014, 56.0); i += 1
    wht  = och(v[i], 0.012, 70.0); i += 1
    bwht = och(v[i], 0.008, 70.0); i += 1
    normal, bright, meta = {}, {}, {}
    for name, hr, lr, cr, floor in FAMILIES:
        h, ln, cn, dl, cb = v[i:i + 5]; i += 5
        normal[name] = och(ln, cn, h)
        bright[name] = och(ln + dl, cb, h)
        meta[name] = (h, ln, cn, ln + dl, cb)
    ansi = [surf, normal["red"], normal["green"], normal["yellow"],
            normal["blue"], normal["magenta"], normal["cyan"], wht,
            dim, bright["red"], bright["green"], bright["yellow"],
            bright["blue"], bright["magenta"], bright["cyan"], bwht]
    return fg, ansi, meta


def margins(v):
    fg, a, meta = unpack(v)
    m = []
    m.append(("fg body Lc>=90", (apca_lc(fg, BG) - 90.0) / 90.0))
    # ANSI 0: a SURFACE, judged by perceptual distance from bg, not by APCA.
    d0 = deltaE_ok(a[0], BG)
    m.append(("ANSI0 visible dE>=0.045", (d0 - 0.045) / 0.045))
    m.append(("ANSI0 not a 2nd bg dE<=0.115", (0.115 - d0) / 0.115))
    m.append(("ANSI8 comment Lc>=48", (apca_lc(a[8], BG) - 48.0) / 48.0))
    m.append(("ANSI7 Lc>=76", (apca_lc(a[7], BG) - 76.0) / 76.0))
    m.append(("ANSI15 Lc>=94", (apca_lc(a[15], BG) - 94.0) / 94.0))
    m.append(("ANSI7/15 ring dE", (deltaE_ok(a[7], a[15]) - 0.075) / 0.075))
    m.append(("ANSI0/8 ring dE", (deltaE_ok(a[0], a[8]) - 0.14) / 0.14))

    nlc, blc = [], []
    for k, (name, hr, lr, cr, floor) in enumerate(FAMILIES):
        ni, bi = k + 1, k + 9
        ln_lc, br_lc = apca_lc(a[ni], BG), apca_lc(a[bi], BG)
        nlc.append(ln_lc); blc.append(br_lc)
        m.append((f"normal {name} Lc>={floor:.0f}", (ln_lc - floor) / floor))
        m.append((f"bright {name} Lc>={floor + T_BRIGHT_BONUS:.0f}",
                  (br_lc - (floor + T_BRIGHT_BONUS)) / (floor + T_BRIGHT_BONUS)))
        m.append((f"ring {ni}/{bi} dE", (deltaE_ok(a[ni], a[bi]) - T_RING_DE) / T_RING_DE))
    m.append(("normal ring Lc spread", (T_RING_SPREAD - (max(nlc) - min(nlc))) / T_RING_SPREAD))
    m.append(("bright ring Lc spread", (T_RING_SPREAD - (max(blc) - min(blc))) / T_RING_SPREAD))

    NI = {n: i + 1 for i, n in enumerate(NAMES)}
    for x, y in CVD_PAIRS:
        for ring, off in (("normal", 0), ("bright", 8)):
            hx, hy = a[NI[x] + off], a[NI[y] + off]
            m.append((f"hue {ring} {x}/{y}", (deltaE_ok(hx, hy) - T_HUE_DE) / T_HUE_DE))
            for k in ("protan", "deutan"):
                d = deltaE_ok(sim(hx, k), sim(hy, k))
                m.append((f"cvd {k} {ring} {x}/{y}", (d - T_CVD_DE) / T_CVD_DE))
    return m


def score(v):
    ms = [x[1] for x in margins(v)]
    return min(ms) + 0.03 * (sum(ms) / len(ms))


def bounds():
    b = [(0.90, 0.965), (0.255, 0.335), (0.55, 0.70), (0.82, 0.90), (0.945, 0.995)]
    for name, hr, lr, cr, floor in FAMILIES:
        b += [hr, lr, cr, (0.085, 0.140), cr]
    return b


def climb(v, b, iters, temp0=1.0):
    best, bs = list(v), score(v)
    step = np.array([(hi - lo) * 0.28 for lo, hi in b])
    for t in range(iters):
        cand = list(best)
        for _ in range(random.choice([1, 1, 1, 2, 2, 3])):
            k = random.randrange(len(cand))
            lo, hi = b[k]
            cand[k] = min(hi, max(lo, cand[k] + random.gauss(0, step[k])))
        s = score(cand)
        if s > bs:
            best, bs = cand, s
        if t and t % 5000 == 0:
            step *= 0.55
    return best, bs


def main():
    b = bounds()
    best, bs = None, -9e9
    for attempt in range(6):
        v = [random.uniform(lo, hi) for lo, hi in b]
        cand, cs = climb(v, b, 16000)
        if cs > bs:
            best, bs = cand, cs
        print(f"  multistart {attempt + 1}: this {cs:+.4f}   best {bs:+.4f}")
    for r in range(4):
        cand, cs = climb(best, b, 12000)
        if cs > bs:
            best, bs = cand, cs
        print(f"  polish {r + 1}: best {bs:+.4f}")

    fg, ansi, meta = unpack(best)
    cursor = och(0.775, 0.150, 52.0)
    sel = och(0.335, 0.042, 56.0)
    ms = margins(best)
    fails = [(n, x) for n, x in ms if x < 0]

    print("\n" + "=" * 84)
    print(f"CONSTRAINTS: {len(ms) - len(fails)}/{len(ms)} met     final score {bs:+.4f}")
    print("=" * 84)
    for n, x in sorted(fails, key=lambda kv: kv[1]):
        print(f"  UNMET  {n:<40} margin {x:+.3f}")
    print("\n  tightest SATISFIED (the binding constraints):")
    for n, x in [p for p in sorted(ms, key=lambda kv: kv[1]) if p[1] >= 0][:8]:
        print(f"    {n:<40} margin {x:+.3f}")

    print("\n" + "=" * 84)
    print("UMBER — final measured palette")
    print("=" * 84)
    print(f"  background  {BG}  OKLCH(0.197 0.014 61.7)  WCAG-Y {wcag_Y(BG):.5f}  -> dark chrome")
    print(f"  foreground  {fg}  Lc {apca_lc(fg, BG):5.1f}  WCAG {wcag_ratio(fg, BG):5.2f}:1")
    print(f"  cursor      {cursor}  Lc {apca_lc(cursor, BG):5.1f}")
    print(f"  selection   {sel}  dE from bg {deltaE_ok(sel, BG):.3f}")
    nm = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    print()
    for i in range(16):
        label = ("bright " + nm[i - 8]) if i >= 8 else nm[i]
        L, C, H = hex_to_oklch(ansi[i])
        print(f"  {i:>2} {label:<15}{ansi[i]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})"
              f"  Lc {apca_lc(ansi[i], BG):5.1f}  WCAG {wcag_ratio(ansi[i], BG):5.2f}:1")

    print("\n  ring separation (normal -> bright):")
    for i in range(8):
        print(f"    {nm[i]:<8}{ansi[i]} -> {ansi[i+8]}   dE-OK {deltaE_ok(ansi[i], ansi[i+8]):.3f}")

    print("\n  colour-vision safety, worst of protanopia/deuteranopia:")
    NI = {n: i + 1 for i, n in enumerate(NAMES)}
    worst = (9, "")
    for x, y in CVD_PAIRS:
        row = f"    {x:>8}/{y:<8}"
        for ring, off in (("norm", 0), ("brt", 8)):
            hx, hy = ansi[NI[x] + off], ansi[NI[y] + off]
            p = deltaE_ok(sim(hx, "protan"), sim(hy, "protan"))
            d = deltaE_ok(sim(hx, "deutan"), sim(hy, "deutan"))
            row += f"  {ring}: protan {p:.3f} deutan {d:.3f}"
            if min(p, d) < worst[0]:
                worst = (min(p, d), f"{x}/{y} {ring}")
        print(row)
    print(f"\n    worst CVD pair overall: {worst[1]} at dE-OK {worst[0]:.3f}")

    print("\n" + "-" * 84)
    print("SWIFT")
    print("-" * 84)
    print(f'        background: NSColor.fromHex("{BG}")!,')
    print(f'        foreground: NSColor.fromHex("{fg}")!,')
    print(f'        cursor: NSColor.fromHex("{cursor}")!,')
    print("        ansi: [")
    for r in range(4):
        print("            " + ", ".join(f'"{ansi[r*4+c]}"' for c in range(4)) + ",")
    print("        ].map { NSColor.fromHex($0)! }")

    import json
    with open("umber-palette.json", "w") as f:
        json.dump({"background": BG, "foreground": fg, "cursor": cursor,
                   "selection": sel, "ansi": ansi,
                   "score": bs, "unmet": [n for n, _ in fails]}, f, indent=2)
    print("\n  wrote umber-palette.json")


if __name__ == "__main__":
    main()
