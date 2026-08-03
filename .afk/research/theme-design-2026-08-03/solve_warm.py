#!/usr/bin/env python3
"""
solve_warm.py — place red/yellow/green so BOTH rings clear tier 1.

impossibility.py proved tier-1 (0.105) reachable for the normal ring, but its
answer put green at L 0.95, which leaves no headroom for a bright green above it.
So the real constraint set is six slots, not three: each family's normal AND bright
must clear tier 1 against the other two families in the same ring, every slot must
clear its APCA floor, and bright must sit >= 0.075 above normal without exceeding
0.975 (above which sRGB has no chroma left to be a colour with).
"""
import numpy as np
from design_theme import oklch_to_hex, apca_lc, deltaE_ok, simulate

BG = oklch_to_hex(0.190, 0.016, 56.0)[0]
# name, hue, normal chroma, bright chroma, normal floor, bright floor
FAM = [("red", 27.0, 0.140, 0.100, 50.0, 65.0),
       ("yellow", 87.0, 0.140, 0.115, 58.0, 73.0),
       ("green", 150.0, 0.131, 0.106, 60.0, 75.0)]

_c = {}
def H(L, C, h):
    k = (round(L, 3), C, h)
    if k not in _c: _c[k] = oklch_to_hex(*k)[0]
    return _c[k]
_d = {}
def dsim(a, b):
    k = (a, b) if a < b else (b, a)
    if k not in _d:
        _d[k] = min(deltaE_ok(simulate(a, x), simulate(b, x)) for x in ("protan", "deutan"))
    return _d[k]

best = (-9, None)
g = np.arange(0.66, 0.93, 0.01)
d = np.arange(0.075, 0.16, 0.01)
for lr in g:
  for dr in d:
    if lr + dr > 0.975: continue
    hr, hR = H(lr, 0.140, 27.0), H(lr + dr, 0.100, 27.0)
    if apca_lc(hr, BG) < 50 or apca_lc(hR, BG) < 65: continue
    for ly in g:
      for dy in d:
        if ly + dy > 0.975: continue
        hy, hY = H(ly, 0.140, 87.0), H(ly + dy, 0.115, 87.0)
        if apca_lc(hy, BG) < 58 or apca_lc(hY, BG) < 73: continue
        if min(dsim(hr, hy), dsim(hR, hY)) < 0.105: continue
        for lg in g:
          for dg in d:
            if lg + dg > 0.975: continue
            hg, hG = H(lg, 0.131, 150.0), H(lg + dg, 0.106, 150.0)
            if apca_lc(hg, BG) < 60 or apca_lc(hG, BG) < 75: continue
            m = min(dsim(hr, hy), dsim(hy, hg), dsim(hr, hg),
                    dsim(hR, hY), dsim(hY, hG), dsim(hR, hG))
            # prefer the solution that is ALSO closest to the eye-approved lightnesses
            pen = abs(lr-0.719) + abs(ly-0.759) + abs(lg-0.844)
            sc = m - 0.02 * pen
            if m >= 0.105 and sc > best[0]:
                best = (sc, (lr, dr, ly, dy, lg, dg, m))

if best[1] is None:
    print("NO SOLUTION with both rings at tier 1.")
else:
    lr, dr, ly, dy, lg, dg, m = best[1]
    print(f"SOLUTION — both rings clear tier 1 (min pairwise dE {m:.4f})\n")
    for nm, L, D, cn, cb in (("red", lr, dr, 0.140, 0.100),
                             ("yellow", ly, dy, 0.140, 0.115),
                             ("green", lg, dg, 0.131, 0.106)):
        n, b = H(L, cn, {"red":27.0,"yellow":87.0,"green":150.0}[nm]), \
               H(L+D, cb, {"red":27.0,"yellow":87.0,"green":150.0}[nm])
        print(f"  {nm:<7} normal L {L:.3f} {n}  Lc {apca_lc(n,BG):5.1f}   "
              f"bright L {L+D:.3f} {b}  Lc {apca_lc(b,BG):5.1f}   ring dE {deltaE_ok(n,b):.3f}")
    print()
    hr, hy, hg = H(lr,0.140,27.0), H(ly,0.140,87.0), H(lg,0.131,150.0)
    hR, hY, hG = H(lr+dr,0.100,27.0), H(ly+dy,0.115,87.0), H(lg+dg,0.106,150.0)
    for a,b,an,bn in ((hr,hy,"red","yellow"),(hy,hg,"yellow","green"),(hr,hg,"red","green")):
        print(f"  normal {an:>6}/{bn:<6} dE {dsim(a,b):.4f}")
    for a,b,an,bn in ((hR,hY,"red","yellow"),(hY,hG,"yellow","green"),(hR,hG,"red","green")):
        print(f"  bright {an:>6}/{bn:<6} dE {dsim(a,b):.4f}")
