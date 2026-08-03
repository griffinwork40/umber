#!/usr/bin/env python3
"""
verify_umber.py — the palette, hand-placed inside the measured feasible region,
then verified against the same instrument that judged the field.

WHY HAND-PLACED AND NOT OPTIMISED. Three optimiser runs produced three different
failure modes, each satisfying more constraints than the last:

  v1  one constraint (ANSI0 judged in APCA) was mathematically unsatisfiable, so
      the max-min objective had no gradient and the run was unguided noise.
  v2  met a uniform Lc>=60 normal ring by pushing red to #FFA771 at OKLCH hue 51.7
      - peach, not red - pinned against its hue bound, and magenta to near-white.
  v3  fixed the hues and the roles; still shipped a bright magenta at chroma 0.037
      because the chroma floor bounded the REQUEST, not the gamut-mapped RESULT.
  v4  constrained achieved chroma and met every one of 60+ constraints - by maxing
      chroma everywhere, because chroma helps CVD separation and nothing penalised
      garishness. Result: #6BE160 lime, #22FDFF electric cyan.

The suite is necessary and not sufficient: it maps the feasible region and prices
the trade-offs, but it cannot express "tasteful", and an optimiser will exploit
whichever axis was left unbounded. So the tool's real output was the FRONTIER, and
the colours are placed by hand inside it, then verified.

Run: python3 verify_umber.py
"""

from design_theme import (oklch_to_hex, hex_to_oklch, apca_lc, wcag_ratio,
                          deltaE_ok, simulate, wcag_Y)
from benchmark_themes import THEMES, score as bench_score

# ----------------------------------------------------------------- the palette
# Placed inside the region frontier.py mapped. Design rules, all falsifiable:
#   * background warm: OKLCH hue ~56 (raw-umber earth), chroma 0.016 - enough to
#     read as warm beside macOS's cool sidebar material, low enough not to be brown.
#   * normal ring chroma ~0.115-0.140: the band Tokyo Night and Catppuccin occupy,
#     which is well-liked for good reason. NOT the gamut edge.
#   * bright ring = normal L + ~0.095, chroma ~0.095-0.115. Lighter AND still
#     chromatic, which is the pair of properties the whole field drops one of.
#   * ANSI 8 lifted to L 0.715. It is the comment colour, and every theme measured
#     leaves it unreadable (Lc 0-34). This is the single biggest legibility win.
#   * lightness is STAGGERED across the ring on purpose: constant-L is unachievable
#     alongside constant readability (frontier.py), and the spread is what keeps
#     red/green apart under deuteranopia where hue is gone.
SPEC = {
    "background":   (0.190, 0.016,  56.0),
    "foreground":   (0.905, 0.014,  80.0),
    "cursor":       (0.780, 0.145,  52.0),
    "selection":    (0.330, 0.040,  56.0),
}
ANSI_SPEC = [
    ("black",          (0.300, 0.016,  56.0)),
    ("red",            (0.735, 0.135,  25.0)),
    ("green",          (0.790, 0.130, 148.0)),
    ("yellow",         (0.775, 0.140,  82.0)),
    ("blue",           (0.720, 0.130, 258.0)),
    ("magenta",        (0.760, 0.130, 332.0)),
    ("cyan",           (0.785, 0.115, 200.0)),
    ("white",          (0.850, 0.013,  72.0)),
    ("bright black",   (0.715, 0.014,  56.0)),
    ("bright red",     (0.835, 0.100,  25.0)),
    ("bright green",   (0.885, 0.105, 148.0)),
    ("bright yellow",  (0.870, 0.115,  82.0)),
    ("bright blue",    (0.820, 0.098, 258.0)),
    ("bright magenta", (0.855, 0.105, 332.0)),
    ("bright cyan",    (0.880, 0.095, 200.0)),
    ("bright white",   (0.975, 0.006,  72.0)),
]

CVD_PAIRS = [("red", "green"), ("red", "yellow"), ("green", "yellow"),
             ("blue", "magenta"), ("green", "cyan"), ("blue", "cyan"),
             ("red", "magenta"), ("red", "blue"), ("yellow", "cyan")]
NI = {"red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6}


def build():
    px = {k: oklch_to_hex(*v)[0] for k, v in SPEC.items()}
    ansi = [(n, oklch_to_hex(*s)[0]) for n, s in ANSI_SPEC]
    return px, ansi


def main():
    px, ansi = build()
    bg, fg = px["background"], px["foreground"]
    A = [h for _, h in ansi]

    print("=" * 86)
    print("UMBER — final palette, verified")
    print("=" * 86)
    for k in ("background", "foreground", "cursor", "selection"):
        h = px[k]
        L, C, H = hex_to_oklch(h)
        extra = ""
        if k == "background":
            extra = (f"  WCAG-Y {wcag_Y(h):.5f} < 0.179 -> dark chrome"
                     f" (Config.swift lightChromeCutoff)")
        elif k == "selection":
            extra = f"  dE from bg {deltaE_ok(h, bg):.3f}"
        else:
            extra = f"  APCA Lc {apca_lc(h, bg):5.1f}   WCAG {wcag_ratio(h, bg):5.2f}:1"
        print(f"  {k:<11}{h}  OKLCH({L:.3f} {C:.3f} {H:5.1f}){extra}")

    print("\n" + "-" * 86)
    print(f"{'idx':>3} {'slot':<15}{'hex':<9}{'OKLCH':<24}{'APCA Lc':>8}{'WCAG':>9}  role check")
    print("-" * 86)
    ROLE = {0: ("surface", None), 7: ("text grey", 74.0), 8: ("comments", 48.0),
            15: ("bright text", 92.0)}
    for i, (name, h) in enumerate(ansi):
        L, C, H = hex_to_oklch(h)
        lc, wr = apca_lc(h, bg), wcag_ratio(h, bg)
        if i in ROLE:
            role, floor = ROLE[i]
            if floor is None:
                verdict = f"{role}: dE {deltaE_ok(h, bg):.3f} from bg"
            else:
                verdict = f"{role}: {'OK' if lc >= floor else 'FAIL'} (floor {floor:.0f})"
        else:
            floor = 55.0 if i in (1, 2, 9, 10) else (48.0 if i in (4, 12) else 52.0)
            verdict = f"marker: {'OK' if lc >= floor else 'FAIL'} (floor {floor:.0f})"
        print(f"{i:>3} {name:<15}{h:<9}({L:.3f} {C:.3f} {H:5.1f})   {lc:6.1f} {wr:7.2f}:1  {verdict}")

    print("\n" + "-" * 86)
    print("ring separation — normal must be unambiguously darker AND still chromatic")
    print("-" * 86)
    ring_min = 9.0
    for i in range(8):
        n, b = A[i], A[i + 8]
        dn, db = hex_to_oklch(n), hex_to_oklch(b)
        de = deltaE_ok(n, b)
        ring_min = min(ring_min, de)
        print(f"  {ansi[i][0]:<8}{n} -> {b}   dL {db[0]-dn[0]:+.3f}"
              f"   dE-OK {de:.3f}   bright chroma {db[1]:.3f}"
              f"   {'OK' if de >= 0.085 and db[1] >= 0.055 or i in (0,7) else 'CHECK'}")
    print(f"\n  smallest ring dE-OK: {ring_min:.3f}   (field best excluding gruvbox: 0.048)")

    print("\n" + "-" * 86)
    print("colour-vision deficiency — worst of protanopia / deuteranopia, both rings")
    print("-" * 86)
    worst = (9.0, "")
    for x, y in CVD_PAIRS:
        cells = []
        for ring, off in (("norm", 0), ("brt", 8)):
            hx, hy = A[NI[x] + off], A[NI[y] + off]
            p = deltaE_ok(simulate(hx, "protan"), simulate(hy, "protan"))
            d = deltaE_ok(simulate(hx, "deutan"), simulate(hy, "deutan"))
            cells.append(f"{ring} p{p:.3f} d{d:.3f}")
            if min(p, d) < worst[0]:
                worst = (min(p, d), f"{x}/{y} {ring}")
        print(f"  {x:>8}/{y:<8} " + "   ".join(cells))
    print(f"\n  worst pair: {worst[1]} at dE-OK {worst[0]:.3f}")
    print("  NOTE: red/green under deuteranopia is bounded by physics, not tuning —")
    print("  hue is gone, so only the lightness stagger survives, and lowering red's")
    print("  lightness far enough to widen it would drop red below its APCA floor.")
    print("  Umber's structural answer is not colour: the git sidebar already carries")
    print("  a LETTER badge per row (M/A/D/U), which is legible with no colour at all.")

    print("\n" + "=" * 86)
    print("HEAD-TO-HEAD vs the field (same code, same thresholds)")
    print("=" * 86)
    rows = {n: bench_score(n, *t) for n, t in THEMES.items()}
    rows["UMBER (this)"] = bench_score("umber", bg, fg, A)
    print(f"{'theme':<18}{'fg Lc':>7}{'ANSI1-6 mean':>14}{'min':>7}"
          f"{'ANSI8':>8}{'ring dE':>9}{'CVD min':>9}")
    print("-" * 86)
    for n, r in sorted(rows.items(), key=lambda kv: -kv[1]["norm_mean"]):
        star = "  <<<" if n.startswith("UMBER") else ""
        print(f"{n:<18}{r['fg_lc']:7.1f}{r['norm_mean']:14.1f}{r['norm_min']:7.1f}"
              f"{r['dim_lc']:8.1f}{r['ring_min']:9.3f}{r['cvd_min']:9.3f}{star}")
    print("-" * 86)
    u = rows["UMBER (this)"]
    print(f"  ANSI8 (comments): Umber {u['dim_lc']:.1f} vs field best "
          f"{max(r['dim_lc'] for n, r in rows.items() if not n.startswith('UMBER')):.1f}")
    print(f"  ring dE:          Umber {u['ring_min']:.3f} vs field best "
          f"{max(r['ring_min'] for n, r in rows.items() if not n.startswith('UMBER')):.3f}")
    print(f"  CVD min:          Umber {u['cvd_min']:.3f} vs field best "
          f"{max(r['cvd_min'] for n, r in rows.items() if not n.startswith('UMBER')):.3f}")

    print("\n" + "-" * 86)
    print("SWIFT — for Theme.swift")
    print("-" * 86)
    print(f'        background: NSColor.fromHex("{bg}")!,')
    print(f'        foreground: NSColor.fromHex("{fg}")!,')
    print(f'        cursor: NSColor.fromHex("{px["cursor"]}")!,')
    print("        ansi: [")
    for r in range(4):
        print("            " + ", ".join(f'"{A[r*4+c]}"' for c in range(4)) + ",")
    print("        ].map { NSColor.fromHex($0)! }")
    print(f'\n  selection (no Theme field yet): "{px["selection"]}"')

    import json
    with open("umber-palette.json", "w") as f:
        json.dump({"_source": "verify_umber.py (hand-placed, verified)",
                   "background": bg, "foreground": fg, "cursor": px["cursor"],
                   "selection": px["selection"],
                   "ansi": A, "ansi_names": [n for n, _ in ansi],
                   "oklch": {n: list(s) for n, s in ANSI_SPEC}}, f, indent=2)
    print("  wrote umber-palette.json")


if __name__ == "__main__":
    main()
