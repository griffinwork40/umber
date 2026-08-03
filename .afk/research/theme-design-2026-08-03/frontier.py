#!/usr/bin/env python3
"""
frontier.py — what APCA Lc is PHYSICALLY reachable per hue, at a given chroma?

Why: the first optimiser run demanded APCA Lc 62 from all six chromatic normal
slots and could not get red or blue past ~42. That looked like a tuning failure.
It is not: APCA's Y is luminance-weighted (R 0.2127, G 0.7152, B 0.0722), so a
saturated red or blue has intrinsically low Y and therefore low Lc. Raising red's
Lc means desaturating it toward salmon. That is a real trade, and it explains why
every theme in the field misses a uniform Lc floor.

So: measure the frontier, then set per-family targets from it. A target nobody
can hit is a bug in the target.

Run: python3 frontier.py
"""

import numpy as np
from design_theme import oklch_to_hex, apca_lc, hex_to_oklch

BG = oklch_to_hex(0.196, 0.014, 56.0)[0]

HUES = [("red", 30.0), ("vermilion", 42.0), ("orange", 55.0), ("yellow", 90.0),
        ("green", 150.0), ("teal-green", 168.0), ("cyan", 200.0),
        ("azure", 240.0), ("blue", 258.0), ("indigo", 268.0),
        ("magenta", 328.0), ("pink", 348.0)]

CHROMA_FLOORS = [0.05, 0.08, 0.10, 0.12, 0.15]


def max_lc_at_chroma_floor(hue, cfloor):
    """Best APCA Lc reachable at this hue while keeping chroma >= cfloor."""
    best = (0.0, None, None)
    for L in np.arange(0.55, 0.99, 0.005):
        hexv, achieved_c = oklch_to_hex(float(L), 0.40, hue)   # ask for max, get gamut edge
        if achieved_c < cfloor:
            continue
        # now clamp chroma down to exactly the floor to be fair across hues
        hexv2, c2 = oklch_to_hex(float(L), cfloor, hue)
        lc = apca_lc(hexv2, BG)
        if lc > best[0]:
            best = (lc, float(L), hexv2)
    return best


def main():
    print("=" * 92)
    print(f"APCA Lc FRONTIER on background {BG}  (OKLCH 0.196 / 0.014 / 56)")
    print("Each cell: the highest Lc reachable at that hue while holding chroma >= the column")
    print("=" * 92)
    header = f"{'hue family':<14}{'deg':>6}" + "".join(f"{f'C>={c:.2f}':>12}" for c in CHROMA_FLOORS)
    print(header)
    print("-" * 92)
    for name, h in HUES:
        cells = []
        for c in CHROMA_FLOORS:
            lc, L, hx = max_lc_at_chroma_floor(h, c)
            cells.append(f"{lc:6.1f}@L{L:.2f}" if L else "     --     ")
        print(f"{name:<14}{h:6.1f}" + "".join(f"{x:>12}" for x in cells))
    print("-" * 92)
    print("Reading it: at chroma 0.12, a recognisable red tops out well below a green or")
    print("yellow at the same chroma. Any 'uniform Lc floor across all six hues' target is")
    print("therefore either unreachable or a demand to desaturate red and blue into pastels.")

    print("\n" + "=" * 92)
    print("MAXIMUM chroma available per hue at fixed OKLCH lightness (the ring design question)")
    print("=" * 92)
    print(f"{'L':<8}" + "".join(f"{n[:9]:>11}" for n, _ in HUES))
    print("-" * 92)
    for L in [0.66, 0.70, 0.74, 0.78, 0.82, 0.86, 0.90]:
        row = []
        for _, h in HUES:
            _, c = oklch_to_hex(L, 0.40, h)
            row.append(f"{c:.3f}")
        print(f"{L:<8.2f}" + "".join(f"{x:>11}" for x in row))
    print("-" * 92)
    print("This is why a constant-L ring cannot also be constant-chroma: at L 0.78 yellow")
    print("still has ~0.17 to spend while blue has ~0.11 and shrinking. Equal-looking")
    print("brightness and equal saturation are not simultaneously purchasable in sRGB.")

    print("\n" + "=" * 92)
    print("RECOMMENDED per-family Lc floors, derived from the frontier at chroma >= 0.10")
    print("=" * 92)
    for name, h in [("red", 30.0), ("vermilion", 42.0), ("green", 150.0),
                    ("yellow", 90.0), ("blue", 258.0), ("azure", 240.0),
                    ("magenta", 328.0), ("cyan", 200.0)]:
        lc, L, hx = max_lc_at_chroma_floor(h, 0.10)
        print(f"  {name:<12} ceiling Lc {lc:5.1f} at L {L:.2f} -> a sane floor is {lc*0.82:5.1f}")


if __name__ == "__main__":
    main()
