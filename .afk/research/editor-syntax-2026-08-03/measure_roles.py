#!/usr/bin/env python3
"""
Can syntax-highlighting roles be a ROLE MAPPING onto the ANSI ring each palette already
ships, rather than five new invented colours per palette?

Why this is the question. Two of the three shipped palettes are declared verbatim upstream
ports, and ThemeValues.swift:109-110 states the contract: "a preset's job is to be the thing
it claims to be — silently 'fixing' a port makes it a different theme wearing the same name."
Inventing 10 syntax colours for afk-dark and tokyo-night would break exactly that. A role
mapping invents nothing, works for a user's own hex and for `classic` (no palette at all),
and inherits whatever legibility the palette was already measured for.

What this measures, for every candidate mapping, across ALL THREE palettes:
  - APCA Lc of each role against that palette's background   (is it readable at all?)
  - OKLab dE between every role pair                          (can you tell them apart?)
  - worst-case dichromatic dE for the pairs that carry meaning
  - the comment slot specifically, which is the field's universal failure

Run:  python3 measure_roles.py
Reads the palettes as literals below — kept in step with ThemeValues.swift by hand, which is
acceptable because this is a design instrument, not a gate. The GATE is
app/Scripts/check-theme-contrast-harness.swift, which compiles the shipped source.
"""
import sys, os, itertools

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "theme-design-2026-08-03"))
from design_theme import apca_lc, deltaE_ok, simulate, hex_to_oklch, wcag_ratio

# ---------------------------------------------------------------- the shipped palettes
# ThemeValues.swift, HEAD 2d10f8e.
PALETTES = {
    "umber": dict(
        bg="#19120D", fg="#E5DFD6",
        ansi=["#342C26", "#EF7F74", "#8AE49E", "#D7AA32", "#739EF0", "#FFACE9", "#42CBC8",
              "#D3CDC5", "#AAA19B", "#FDAAA0", "#B4FCC3", "#F7D179", "#9DBEFC", "#FFD2F2",
              "#80E5E2", "#F9F6F2"]),
    "afk-dark": dict(
        bg="#0D1117", fg="#C9D1D9",
        ansi=["#161B22", "#F85149", "#9CB04A", "#E5C07B", "#5BA8FF", "#9F7CE0", "#56B5A8",
              "#C9D1D9", "#484F58", "#F85149", "#A8E060", "#E67E4C", "#5BA8FF", "#F08AC4",
              "#5FE0C0", "#ECEFF4"]),
    "tokyo-night": dict(
        bg="#1A1B26", fg="#C0CAF5",
        ansi=["#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF",
              "#A9B1D6", "#414868", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7",
              "#7DCFFF", "#C0CAF5"]),
}

SLOT = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
        "br-black", "br-red", "br-green", "br-yellow", "br-blue", "br-magenta",
        "br-cyan", "br-white"]

# ---------------------------------------------------------------- candidate mappings
# Each is role -> ANSI index. base16's template is the most widely deployed ANSI-16 syntax
# mapping in existence (string=0B green, keyword=0E magenta, constant=09 orange, type=0A
# yellow, comment=03) and every candidate here is a reading of it constrained to 6 chromatic
# slots. ANSI 0 (a surface, not text) and 7/15 (plain text) are never used for a role.
CANDIDATES = {
    "base16-ish":  dict(keyword=5, string=2, number=3, type=6, comment=8),
    "type-yellow": dict(keyword=5, string=2, number=1, type=3, comment=8),
    "kw-blue":     dict(keyword=4, string=2, number=3, type=6, comment=8),
    "vscode-ish":  dict(keyword=4, string=3, number=2, type=6, comment=8),
}

# Pairs a reader must be able to tell apart to read code correctly. keyword/type and
# string/number are the load-bearing ones: they are adjacent constantly (`let x: Int = 3`,
# `{"k": 1}`) and confusing them is confusing structure for content.
ROLE_PAIRS = [("keyword", "type"), ("string", "number"), ("keyword", "string"),
              ("keyword", "number"), ("type", "number"), ("type", "string")]

READABLE = 45.0   # APCA: the floor below which text is not readable at ANY size
MARKER = 55.0     # what the repo's own ANSI floors sit at for chromatic slots that carry lines


def worst_cvd(a, b):
    return min(deltaE_ok(simulate(a, k), simulate(b, k))
               for k in ("protanopia", "deuteranopia", "tritanopia"))


def composited(fg, bg, alpha):
    """fg drawn at `alpha` over opaque bg — the arithmetic RGB.composited(over:alpha:) does."""
    f = [int(fg[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(bg[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(f[i] * alpha + b[i] * (1 - alpha)):02X}" for i in range(3))


print("=" * 78)
print("1. IS THE ANSI RING READABLE AT ALL, PER PALETTE?  (APCA Lc vs background)")
print("=" * 78)
for name, p in PALETTES.items():
    print(f"\n{name}:  fg={apca_lc(p['fg'], p['bg']):5.1f}")
    for i in (1, 2, 3, 4, 5, 6, 8):
        lc = apca_lc(p["ansi"][i], p["bg"])
        flag = "" if lc >= MARKER else ("  <- below READABLE 45" if lc < READABLE else "  <- 45..55")
        print(f"   ansi[{i}] {SLOT[i]:<9} {p['ansi'][i]}  Lc {lc:5.1f}{flag}")

print()
print("=" * 78)
print("2. CANDIDATE MAPPINGS")
print("=" * 78)
for cname, m in CANDIDATES.items():
    print(f"\n--- {cname}: " + ", ".join(f"{r}=ansi[{i}]" for r, i in m.items()))
    for pname, p in PALETTES.items():
        lcs = {r: apca_lc(p["ansi"][i], p["bg"]) for r, i in m.items()}
        worst_role = min(lcs, key=lcs.get)
        pairs = {f"{x}/{y}": deltaE_ok(p["ansi"][m[x]], p["ansi"][m[y]]) for x, y in ROLE_PAIRS}
        cvd = {f"{x}/{y}": worst_cvd(p["ansi"][m[x]], p["ansi"][m[y]]) for x, y in ROLE_PAIRS}
        print(f"  {pname:<12} min Lc {lcs[worst_role]:5.1f} ({worst_role})"
              f"   min dE {min(pairs.values()):.3f} ({min(pairs, key=pairs.get)})"
              f"   min CVD dE {min(cvd.values()):.3f} ({min(cvd, key=cvd.get)})")
        bad = [r for r, v in lcs.items() if v < READABLE]
        if bad:
            print(f"               UNREADABLE: " + ", ".join(f"{r} Lc {lcs[r]:.1f}" for r in bad))

print()
print("=" * 78)
print("3. THE COMMENT SLOT — ansi[8] is the field's universal failure")
print("=" * 78)
for pname, p in PALETTES.items():
    lc = apca_lc(p["ansi"][8], p["bg"])
    print(f"  {pname:<12} ansi[8]={p['ansi'][8]}  Lc {lc:5.1f}"
          f"  {'OK' if lc >= READABLE else 'UNREADABLE'}")
print()
print("  Fallback candidate: foreground composited over background at alpha.")
print("  (Same arithmetic the tab strip already uses for de-emphasis; its inactive")
print("   label alpha is 0.72, chosen by the gate for exactly this reason.)")
hdr = "  alpha   " + "".join(f"{n:>14}" for n in PALETTES)
print(hdr)
for alpha in (0.50, 0.55, 0.60, 0.65, 0.70, 0.72, 0.75):
    row = f"  {alpha:.2f}    "
    for pname, p in PALETTES.items():
        c = composited(p["fg"], p["bg"], alpha)
        row += f"{apca_lc(c, p['bg']):9.1f} {c[:7]}"[:14].rjust(14)
    print(row)
print()
for alpha in (0.60, 0.65, 0.70, 0.72):
    lcs = [apca_lc(composited(p["fg"], p["bg"], alpha), p["bg"]) for p in PALETTES.values()]
    gaps = [apca_lc(p["fg"], p["bg"]) - l for p, l in zip(PALETTES.values(), lcs)]
    print(f"  alpha {alpha:.2f}: min Lc {min(lcs):5.1f}  |  gap below body text "
          f"{min(gaps):5.1f}..{max(gaps):5.1f} Lc")

print()
print("=" * 78)
print("4. WOULD THE FALLBACK BRANCH BE EXERCISED? (gate reachability)")
print("=" * 78)
for pname, p in PALETTES.items():
    lc = apca_lc(p["ansi"][8], p["bg"])
    print(f"  {pname:<12} takes {'ANSI-8' if lc >= READABLE else 'FALLBACK'} path (Lc {lc:.1f})")
