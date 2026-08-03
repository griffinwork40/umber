#!/usr/bin/env python3
"""
impossibility.py — is the red/yellow/green three-way separable under deuteranopia?

The eye-correction broke red/yellow and green/yellow at tier 1 (dE 0.105). Before
lowering a threshold to make the run pass — the exact failure mode this whole
exercise has been criticising — establish whether ANY assignment satisfies it.

Deuteranopia collapses red, yellow and green onto one axis, so the only surviving
signal is lightness. Three mutually-separated slots therefore need ~2x the pairwise
gap in total span. Grid-search every lightness triple at the shipped hues/chromas
and report the best achievable min-pairwise separation subject to the APCA floors.
"""
import numpy as np
from design_theme import oklch_to_hex, apca_lc, deltaE_ok, simulate

BG = oklch_to_hex(0.190, 0.016, 56.0)[0]
# (name, hue, chroma, APCA floor) — as shipped
SLOTS = [("red", 27.0, 0.140, 50.0), ("yellow", 87.0, 0.140, 58.0),
         ("green", 150.0, 0.131, 60.0)]

def dsim(h1, h2):
    return min(deltaE_ok(simulate(h1, k), simulate(h2, k)) for k in ("protan", "deutan"))

best = (0.0, None)
best_unconstrained = (0.0, None)
grid = np.arange(0.62, 0.96, 0.01)
for lr in grid:
    hr = oklch_to_hex(float(lr), 0.140, 27.0)[0]
    ok_r = apca_lc(hr, BG) >= 50.0
    for ly in grid:
        hy = oklch_to_hex(float(ly), 0.140, 87.0)[0]
        ok_y = apca_lc(hy, BG) >= 58.0
        for lg in grid:
            hg = oklch_to_hex(float(lg), 0.131, 150.0)[0]
            ok_g = apca_lc(hg, BG) >= 60.0
            m = min(dsim(hr, hy), dsim(hy, hg), dsim(hr, hg))
            if m > best_unconstrained[0]:
                best_unconstrained = (m, (lr, ly, lg))
            if ok_r and ok_y and ok_g and m > best[0]:
                best = (m, (lr, ly, lg))

print(f"background {BG}")
print(f"\nBEST min-pairwise dichromacy separation for red/yellow/green")
print(f"  subject to APCA floors (50/58/60): dE {best[0]:.4f}")
if best[1]:
    lr, ly, lg = best[1]
    print(f"    at L red {lr:.2f}  yellow {ly:.2f}  green {lg:.2f}")
    for a, b in (("red","yellow"),("yellow","green"),("red","green")):
        L = {"red":(lr,0.140,27.0),"yellow":(ly,0.140,87.0),"green":(lg,0.131,150.0)}
        print(f"    {a:>6}/{b:<6} dE {dsim(oklch_to_hex(*L[a])[0], oklch_to_hex(*L[b])[0]):.4f}")
print(f"\n  ignoring APCA floors entirely: dE {best_unconstrained[0]:.4f} "
      f"at L {tuple(round(x,2) for x in best_unconstrained[1])}")
print(f"\nCONCLUSION: tier-1 (0.105) for all three pairs is "
      f"{'ACHIEVABLE' if best[0] >= 0.105 else 'NOT ACHIEVABLE'}.")
print(f"The reachable ceiling with floors enforced is {best[0]:.3f}, so a threshold above")
print(f"that is a demand no sRGB palette on this background can meet.")
