#!/usr/bin/env python3
"""
final.py — the shipped palette. Searched, then corrected by eye, then re-verified.

The search (place_final.py) put red at OKLCH hue 18.2 and green at 157.2, both
pinned against their bounds, because that maximised red/green separation under
deuteranopia. Rendered on real content (preview.py) those read as salmon-pink and
mint — the numbers were right and the colours were wrong. Red moves to hue 27 and
green to 150, which costs red/green CVD margin. This file proves what the cost is
rather than hoping it is small: the tier-1 floor is still asserted, and if the
correction had broken it the assertion below would fail.

Everything else is the searched result unchanged.

Run: python3 final.py
"""

import json
from design_theme import (oklch_to_hex, hex_to_oklch, apca_lc, wcag_ratio,
                          deltaE_ok, simulate, wcag_Y)

# OKLCH (L, C, H) -> the shipped values. Kept in OKLCH, not hex, because the hex is
# a rendering of a decision and the decision is the lightness/chroma/hue triple.
SPEC = {
    "background": (0.190, 0.016,  56.0),   # warm umber-black
    "foreground": (0.905, 0.014,  80.0),   # warm paper
    "cursor":     (0.780, 0.145,  52.0),   # umber-orange caret
    "selection":  (0.330, 0.040,  56.0),   # a warm lift of the background
}
ANSI = [
    ("black",          (0.300, 0.016,  56.0)),
    ("red",            (0.720, 0.140,  27.0)),   # was 18.2 (salmon); 27 reads red
    ("green",          (0.845, 0.131, 150.0)),   # was 157.2 (mint); 150 reads green
    ("yellow",         (0.759, 0.140,  87.0)),
    ("blue",           (0.702, 0.130, 262.5)),
    ("magenta",        (0.842, 0.129, 337.0)),   # was 323 (lilac); 337 reads pink-magenta
    ("cyan",           (0.770, 0.115, 192.9)),
    ("white",          (0.851, 0.013,  74.0)),
    ("bright black",   (0.715, 0.014,  56.0)),   # the comment colour. The field's failure.
    ("bright red",     (0.816, 0.100,  27.0)),
    ("bright green",   (0.930, 0.106, 150.0)),
    ("bright yellow",  (0.875, 0.115,  87.0)),
    ("bright blue",    (0.800, 0.096, 262.5)),
    ("bright magenta", (0.912, 0.078, 337.0)),
    ("bright cyan",    (0.860, 0.095, 192.9)),
    ("bright white",   (0.974, 0.006,  74.0)),
]

TIER = {("red", "green"): 0.105, ("red", "yellow"): 0.105, ("green", "yellow"): 0.105,
        ("blue", "magenta"): 0.080, ("green", "cyan"): 0.080, ("blue", "cyan"): 0.080,
        ("red", "magenta"): 0.080, ("red", "blue"): 0.080,
        ("magenta", "cyan"): 0.050, ("yellow", "magenta"): 0.050,
        ("yellow", "cyan"): 0.050, ("blue", "green"): 0.050}
NI = {"red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6}

# ACCEPTED SHORTFALLS — pairs that miss their tier, with the reason and the rejected
# alternative. Recorded here rather than by lowering the tier, because a threshold
# quietly relaxed to make a run pass is indistinguishable from never having had one.
# solve_warm.py PROVED tier 1 reachable for all three warm pairs at yellow L 0.810 /
# green L 0.890; preview2.html shows what that costs — a washed mint green and a
# near-white bright green (#D9FFE0), visibly worse on `git diff` and `✔`. Taste won,
# on the record, and a reviewer can overturn it by reading the same two artifacts.
SHORTFALL = {
    ("red", "yellow"): ("0.080", "three-way red/yellow/green under deuteranopia needs a "
                        "~0.21 lightness span; taking it washes out green (solve_warm.py, "
                        "preview2.html). Error-vs-warning is also carried by the words."),
    ("green", "yellow"): ("0.080", "same three-way constraint; same rejected alternative."),
    ("magenta", "cyan"): ("0.025", "tier-3 cosmetic adjacency. No tool contrasts magenta "
                          "with cyan semantically; nothing is misread if they converge."),
}
ROLE_FLOOR = {1: 50.0, 2: 60.0, 3: 58.0, 4: 48.0, 5: 56.0, 6: 60.0,
              9: 65.0, 10: 75.0, 11: 73.0, 12: 63.0, 13: 71.0, 14: 75.0,
              7: 74.0, 8: 48.0, 15: 92.0}


def build():
    px = {k: oklch_to_hex(*v)[0] for k, v in SPEC.items()}
    a = [oklch_to_hex(*s)[0] for _, s in ANSI]
    return px, a


def main():
    px, A = build()
    bg, fg = px["background"], px["foreground"]
    failures = []

    print("=" * 84)
    print("UMBER — shipped palette, verified")
    print("=" * 84)
    for k in ("background", "foreground", "cursor", "selection"):
        L, C, H = hex_to_oklch(px[k])
        tail = (f"WCAG-Y {wcag_Y(px[k]):.5f} -> dark chrome" if k == "background"
                else f"dE from bg {deltaE_ok(px[k], bg):.3f}" if k == "selection"
                else f"Lc {apca_lc(px[k], bg):5.1f}  WCAG {wcag_ratio(px[k], bg):5.2f}:1")
        print(f"  {k:<11}{px[k]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})  {tail}")
    if wcag_Y(bg) > 0.179:
        failures.append("background luminance above lightChromeCutoff")
    if apca_lc(fg, bg) < 85:
        failures.append(f"foreground Lc {apca_lc(fg, bg):.1f} < 85")

    print("\n" + "-" * 84)
    for i, (name, _) in enumerate(ANSI):
        L, C, H = hex_to_oklch(A[i])
        lc = apca_lc(A[i], bg)
        floor = ROLE_FLOOR.get(i)
        if i == 0:
            d = deltaE_ok(A[i], bg)
            ok = "OK" if 0.05 <= d <= 0.14 else "CHECK"
            note = f"surface dE {d:.3f}  {ok}"
            if ok != "OK":
                failures.append(f"ANSI0 surface dE {d:.3f} outside 0.05-0.14")
        else:
            ok = "OK" if lc >= floor else "FAIL"
            note = f"floor {floor:.0f}  {ok}"
            if ok == "FAIL":
                failures.append(f"ANSI{i} {name} Lc {lc:.1f} < {floor:.0f}")
        print(f"  {i:>2} {name:<15}{A[i]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})"
              f"  Lc {lc:5.1f}  WCAG {wcag_ratio(A[i], bg):5.2f}:1  {note}")

    print("\n  ring separation (dE-OK >= 0.085 required):")
    for i in range(8):
        de = deltaE_ok(A[i], A[i + 8])
        if de < 0.085:
            failures.append(f"ring {i}/{i+8} dE {de:.3f} < 0.085")
        print(f"    {ANSI[i][0]:<8}{A[i]} -> {A[i+8]}  dE {de:.3f}"
              f"  {'OK' if de >= 0.085 else 'FAIL'}")

    print("\n  dichromacy, worst of protanopia/deuteranopia, vs the pair's TIER:")
    for (x, y), tier in sorted(TIER.items(), key=lambda kv: -kv[1]):
        vals, worst = [], 9.0
        for ring, off in (("norm", 0), ("brt", 8)):
            hx, hy = A[NI[x] + off], A[NI[y] + off]
            p = deltaE_ok(simulate(hx, "protan"), simulate(hy, "protan"))
            d = deltaE_ok(simulate(hx, "deutan"), simulate(hy, "deutan"))
            vals.append(f"{ring} p{p:.3f} d{d:.3f}")
            worst = min(worst, p, d)
        sf = SHORTFALL.get((x, y))
        eff = float(sf[0]) if sf else tier
        ok = "OK" if worst >= eff else "FAIL"
        tag = ok if not sf else (f"ACCEPTED (>= {sf[0]})" if worst >= eff else "FAIL")
        if worst < eff:
            failures.append(f"cvd {x}/{y} {worst:.3f} < {eff:.3f}")
        print(f"    {x:>8}/{y:<8} " + "  ".join(vals) + f"   tier {tier:.3f}  {tag}")
    if SHORTFALL:
        print("\n  accepted shortfalls (tier missed deliberately, reason on record):")
        for (x, y), (lim, why) in SHORTFALL.items():
            print(f"    {x}/{y} -> accepted at {lim}: {why}")

    from benchmark_themes import THEMES, score as bsc
    rows = {n: bsc(n, *t) for n, t in THEMES.items()}
    rows["UMBER"] = bsc("umber", bg, fg, A)
    print("\n" + "=" * 84)
    print("HEAD-TO-HEAD (same code, same thresholds, sorted by mean normal-ring Lc)")
    print("=" * 84)
    print(f"{'theme':<18}{'fg Lc':>7}{'ANSI1-6':>9}{'min':>7}{'ANSI8':>8}"
          f"{'ring dE':>9}{'CVD min':>9}")
    print("-" * 84)
    for n, r in sorted(rows.items(), key=lambda kv: -kv[1]["norm_mean"]):
        print(f"{n:<18}{r['fg_lc']:7.1f}{r['norm_mean']:9.1f}{r['norm_min']:7.1f}"
              f"{r['dim_lc']:8.1f}{r['ring_min']:9.3f}{r['cvd_min']:9.3f}"
              f"{'  <<<' if n == 'UMBER' else ''}")

    print("\n" + "=" * 84)
    if failures:
        print(f"VERDICT: {len(failures)} ASSERTION(S) FAILED")
        for f in failures:
            print(f"  - {f}")
    else:
        print("VERDICT: every asserted target met")
    print("=" * 84)

    print("\nSWIFT\n" + "-" * 84)
    print(f'        background: NSColor.fromHex("{bg}")!,')
    print(f'        foreground: NSColor.fromHex("{fg}")!,')
    print(f'        cursor: NSColor.fromHex("{px["cursor"]}")!,')
    print("        ansi: [")
    for r in range(4):
        print("            " + ", ".join(f'"{A[r*4+c]}"' for c in range(4)) + ",")
    print("        ].map { NSColor.fromHex($0)! }")

    with open("umber-palette.json", "w") as f:
        json.dump({"_source": "final.py — searched then eye-corrected then re-verified",
                   "background": bg, "foreground": fg, "cursor": px["cursor"],
                   "selection": px["selection"], "ansi": A,
                   "ansi_names": [n for n, _ in ANSI],
                   "oklch": {n: list(s) for n, s in ANSI},
                   "failures": failures}, f, indent=2)
    print("\n  wrote umber-palette.json")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
