#!/usr/bin/env python3
"""
Exhaustive rank of role->ANSI-slot mappings, so the shipped one is CHOSEN rather than
inherited from whichever convention was recalled first.

Search space: assign the four chromatic roles (keyword, string, number, type) to distinct
slots drawn from the six chromatic ANSI indices {1..6}. That is 6*5*4*3 = 360 mappings.
ANSI 0 is excluded (a surface, not text — ThemeValues.swift:86) and 7/15 are excluded (they
ARE plain text, so a role wearing them is invisible as a role). `comment` is fixed at 8: it is
the one slot every terminal tool already uses for de-emphasis, and umber's ANSI 8 was designed
for precisely that job (ThemeValues.swift:94, "the comment colour").

Ranked by what actually breaks a highlighter, in priority order:
  1. worst-case dichromatic dE across the load-bearing role pairs, under UMBER
     (umber is the only palette held to design floors — check-theme-contrast-harness.swift:156)
  2. minimum APCA Lc across roles under umber
  3. how many roles fall below APCA 45 across the two verbatim ports (lower is better)

Run: python3 rank_mappings.py
"""
import sys, os, itertools

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "theme-design-2026-08-03"))
from design_theme import apca_lc, deltaE_ok, simulate
from measure_roles import PALETTES, SLOT, ROLE_PAIRS, READABLE, worst_cvd, composited

ROLES = ["keyword", "string", "number", "type"]
CHROMATIC = [1, 2, 3, 4, 5, 6]
UMBER = PALETTES["umber"]
PORTS = {k: v for k, v in PALETTES.items() if k != "umber"}


def evaluate(m):
    """m: role -> ansi index (comment excluded; it is always 8)."""
    lcs = {r: apca_lc(UMBER["ansi"][i], UMBER["bg"]) for r, i in m.items()}
    cvd = {f"{x}/{y}": worst_cvd(UMBER["ansi"][m[x]], UMBER["ansi"][m[y]])
           for x, y in ROLE_PAIRS}
    de = {f"{x}/{y}": deltaE_ok(UMBER["ansi"][m[x]], UMBER["ansi"][m[y]])
          for x, y in ROLE_PAIRS}
    port_fails = sum(1 for p in PORTS.values() for i in m.values()
                     if apca_lc(p["ansi"][i], p["bg"]) < READABLE)
    return dict(min_cvd=min(cvd.values()), min_lc=min(lcs.values()), min_de=min(de.values()),
                port_fails=port_fails, lcs=lcs, cvd=cvd, de=de,
                worst_cvd_pair=min(cvd, key=cvd.get))


rows = []
for combo in itertools.permutations(CHROMATIC, len(ROLES)):
    m = dict(zip(ROLES, combo))
    rows.append((m, evaluate(m)))

rows.sort(key=lambda r: (-r[1]["min_cvd"], -r[1]["min_lc"], r[1]["port_fails"]))

print(f"Ranked {len(rows)} mappings. Top 12 by (umber worst-CVD, umber min-Lc, port failures):\n")
print(f"{'kw':<9}{'str':<9}{'num':<9}{'type':<9}  {'minCVD':>7}{'minLc':>7}{'minDE':>7}"
      f"{'portFail':>9}   worst CVD pair")
for m, e in rows[:12]:
    print(f"{SLOT[m['keyword']]:<9}{SLOT[m['string']]:<9}{SLOT[m['number']]:<9}"
          f"{SLOT[m['type']]:<9}  {e['min_cvd']:7.3f}{e['min_lc']:7.1f}{e['min_de']:7.3f}"
          f"{e['port_fails']:9d}   {e['worst_cvd_pair']}")

print("\nWhere the convention-preferred mappings rank (string=green is near-universal):")
for label, m in [("base16 (kw=magenta,type=cyan)", dict(keyword=5, string=2, number=3, type=6)),
                 ("base16-strict (type=yellow)", dict(keyword=5, string=2, number=1, type=3)),
                 ("kw-blue (kw=blue,type=cyan)", dict(keyword=4, string=2, number=3, type=6)),
                 ("kw-magenta,num=cyan", dict(keyword=5, string=2, number=6, type=3))]:
    rank = next(i for i, (mm, _) in enumerate(rows) if mm == m) + 1
    e = evaluate(m)
    print(f"  #{rank:<4} {label:<32} minCVD {e['min_cvd']:.3f}  minLc {e['min_lc']:5.1f}  "
          f"portFail {e['port_fails']}  worst {e['worst_cvd_pair']}")

# ------------------------------------------------------------------ chosen, in full
BEST = rows[0][0]
print("\n" + "=" * 78)
print("FULL DETAIL — best-ranked mapping, all palettes")
print("=" * 78)
CHOSEN = dict(BEST)
CHOSEN["comment"] = 8
print("  " + ", ".join(f"{r}=ansi[{i}] ({SLOT[i]})" for r, i in CHOSEN.items()))
COMMENT_ALPHA = 0.72
for pname, p in PALETTES.items():
    print(f"\n  {pname}  (bg {p['bg']}, fg {p['fg']} at Lc {apca_lc(p['fg'], p['bg']):.1f})")
    for r, i in CHOSEN.items():
        hexv, note = p["ansi"][i], ""
        lc = apca_lc(hexv, p["bg"])
        if r == "comment" and lc < READABLE:
            hexv = composited(p["fg"], p["bg"], COMMENT_ALPHA)
            lc = apca_lc(hexv, p["bg"])
            note = f"  (ansi[8] was Lc {apca_lc(p['ansi'][8], p['bg']):.1f} -> FALLBACK a={COMMENT_ALPHA})"
        print(f"    {r:<8} {hexv}  Lc {lc:5.1f}{'  <45 !!' if lc < READABLE else ''}{note}")
    resolved = {}
    for r, i in CHOSEN.items():
        h = p["ansi"][i]
        if r == "comment" and apca_lc(h, p["bg"]) < READABLE:
            h = composited(p["fg"], p["bg"], COMMENT_ALPHA)
        resolved[r] = h
    print("    pairwise (dE / worst-CVD dE):")
    for x, y in ROLE_PAIRS + [("comment", "keyword"), ("comment", "string")]:
        print(f"      {x + '/' + y:<18} {deltaE_ok(resolved[x], resolved[y]):.3f}"
              f" / {worst_cvd(resolved[x], resolved[y]):.3f}")
