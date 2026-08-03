#!/usr/bin/env python3
"""
benchmark_themes.py — score the field with the same instrument.

Purpose: calibration, not scoring for its own sake. Before asserting a target
("every ANSI slot must clear APCA Lc 60") I have to know whether ANY shipped
theme clears it. If none do, the target is wrong; if some do, it is achievable
and the ones that miss are the failure modes worth avoiding by name.

Palettes are transcribed from each project's own published values. Sources are
recorded in the SOURCES dict and in the design doc beside this file.

Run: python3 benchmark_themes.py
"""

from design_theme import (apca_lc, wcag_ratio, hex_to_oklch, deltaE_ok,
                          simulate, wcag_Y)

SOURCES = {
    "solarized-dark": "ethanschoonover.com/solarized (base03 bg, base0 fg)",
    "tokyo-night":    "github.com/folke/tokyonight.nvim (storm/night terminal block)",
    "catppuccin-mocha": "github.com/catppuccin/catppuccin style-guide.md",
    "nord":           "nordtheme.com/docs/colors-and-palettes",
    "github-dark":    "primer.style/foundations/color (dark default)",
    "rose-pine":      "rosepinetheme.com/palette",
    "gruvbox-dark":   "github.com/morhetz/gruvbox (dark, medium)",
    "afk-dark":       "app/Sources/Umber/Theme.swift (Umber's own preset)",
    "xterm-default":  "the historical xterm/VGA 16 — the no-theme baseline",
}

THEMES = {
    # bg, fg, ansi[16]
    "solarized-dark": ("#002B36", "#839496", [
        "#073642", "#DC322F", "#859900", "#B58900",
        "#268BD2", "#D33682", "#2AA198", "#EEE8D5",
        "#002B36", "#CB4B16", "#586E75", "#657B83",
        "#839496", "#6C71C4", "#93A1A1", "#FDF6E3"]),
    "tokyo-night": ("#1A1B26", "#C0CAF5", [
        "#15161E", "#F7768E", "#9ECE6A", "#E0AF68",
        "#7AA2F7", "#BB9AF7", "#7DCFFF", "#A9B1D6",
        "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
        "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]),
    "catppuccin-mocha": ("#1E1E2E", "#CDD6F4", [
        "#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF",
        "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE",
        "#585B70", "#F38BA8", "#A6E3A1", "#F9E2AF",
        "#89B4FA", "#F5C2E7", "#94E2D5", "#A6ADC8"]),
    "nord": ("#2E3440", "#D8DEE9", [
        "#3B4252", "#BF616A", "#A3BE8C", "#EBCB8B",
        "#81A1C1", "#B48EAD", "#88C0D0", "#E5E9F0",
        "#4C566A", "#BF616A", "#A3BE8C", "#EBCB8B",
        "#81A1C1", "#B48EAD", "#8FBCBB", "#ECEFF4"]),
    "github-dark": ("#0D1117", "#C9D1D9", [
        "#484F58", "#FF7B72", "#3FB950", "#D29922",
        "#58A6FF", "#BC8CFF", "#39C5CF", "#B1BAC4",
        "#6E7681", "#FFA198", "#56D364", "#E3B341",
        "#79C0FF", "#D2A8FF", "#56D4DD", "#F0F6FC"]),
    "rose-pine": ("#191724", "#E0DEF4", [
        "#26233A", "#EB6F92", "#31748F", "#F6C177",
        "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4",
        "#6E6A86", "#EB6F92", "#31748F", "#F6C177",
        "#9CCFD8", "#C4A7E7", "#EBBCBA", "#E0DEF4"]),
    "gruvbox-dark": ("#282828", "#EBDBB2", [
        "#282828", "#CC241D", "#98971A", "#D79921",
        "#458588", "#B16286", "#689D6A", "#A89984",
        "#928374", "#FB4934", "#B8BB26", "#FABD2F",
        "#83A598", "#D3869B", "#8EC07C", "#EBDBB2"]),
    "afk-dark": ("#0D1117", "#C9D1D9", [
        "#161B22", "#F85149", "#9CB04A", "#E5C07B",
        "#5BA8FF", "#9F7CE0", "#56B5A8", "#C9D1D9",
        "#484F58", "#F85149", "#A8E060", "#E67E4C",
        "#5BA8FF", "#F08AC4", "#5FE0C0", "#ECEFF4"]),
    "xterm-default": ("#000000", "#FFFFFF", [
        "#000000", "#CD0000", "#00CD00", "#CDCD00",
        "#0000EE", "#CD00CD", "#00CDCD", "#E5E5E5",
        "#7F7F7F", "#FF0000", "#00FF00", "#FFFF00",
        "#5C5CFF", "#FF00FF", "#00FFFF", "#FFFFFF"]),
}

CVD_PAIRS = [(1, 2, "red/green"), (9, 10, "bright red/green"),
             (1, 3, "red/yellow"), (4, 5, "blue/magenta"),
             (2, 6, "green/cyan")]


def score(name, bg, fg, ansi):
    fg_lc = apca_lc(fg, bg)
    # normal ring = slots 1..6 (the chromatic ones that carry real output);
    # slot 0 is a surface, slot 7 is a text grey, both judged separately.
    normal = [apca_lc(ansi[i], bg) for i in range(1, 7)]
    bright = [apca_lc(ansi[i], bg) for i in range(9, 15)]
    dim_lc = apca_lc(ansi[8], bg)          # bright-black: the comment colour
    ring_de = [deltaE_ok(ansi[i], ansi[i + 8]) for i in range(8)]
    cvd_min = 99.0
    cvd_detail = {}
    for a, b, why in CVD_PAIRS:
        worst = min(deltaE_ok(simulate(ansi[a], k), simulate(ansi[b], k))
                    for k in ("protan", "deutan"))
        cvd_detail[why] = worst
        cvd_min = min(cvd_min, worst)
    return dict(fg_lc=fg_lc, norm_min=min(normal), norm_mean=sum(normal) / 6,
                brt_min=min(bright), dim_lc=dim_lc,
                ring_min=min(ring_de), cvd_min=cvd_min, cvd=cvd_detail,
                bg_Y=wcag_Y(bg), bg_hue=hex_to_oklch(bg)[2],
                bg_chroma=hex_to_oklch(bg)[1])


def main():
    rows = {n: score(n, *t) for n, t in THEMES.items()}
    print("=" * 100)
    print("FIELD CALIBRATION — every number produced by the same code that will judge Umber's")
    print("=" * 100)
    print(f"{'theme':<18}{'fg Lc':>6}{'ANSI1-6 Lc':>13}{'min':>6}"
          f"{'brt min':>9}{'ANSI8 Lc':>10}{'ring dE':>9}{'CVD min':>9}")
    print("-" * 100)
    for n, r in sorted(rows.items(), key=lambda kv: -kv[1]["norm_mean"]):
        print(f"{n:<18}{r['fg_lc']:6.1f}{r['norm_mean']:10.1f}   {r['norm_min']:6.1f}"
              f"{r['brt_min']:9.1f}{r['dim_lc']:10.1f}{r['ring_min']:9.3f}{r['cvd_min']:9.3f}")
    print("-" * 100)
    print("fg Lc      : foreground on background. APCA: 90 preferred body, 75 minimum body.")
    print("ANSI1-6 Lc : mean/min APCA of the six chromatic normal slots on bg. 60 = readable floor.")
    print("brt min    : worst of the six chromatic BRIGHT slots.")
    print("ANSI8 Lc   : bright-black, i.e. what most schemes colour comments with.")
    print("ring dE    : smallest normal->bright dE-OK across all 8 pairs. <0.05 = the")
    print("             'bright is identical to normal' bug (Solarized, Catppuccin, Tokyo Night).")
    print("CVD min    : worst protanopia/deuteranopia dE-OK over the 5 pairs a terminal needs.")

    print("\n" + "=" * 100)
    print("WHERE THE FAMOUS THEMES ACTUALLY FAIL")
    print("=" * 100)
    for n, r in rows.items():
        faults = []
        if r["fg_lc"] < 75:  faults.append(f"body text below APCA min body (Lc {r['fg_lc']:.0f})")
        if r["norm_min"] < 60: faults.append(f"a normal ANSI slot at Lc {r['norm_min']:.0f}")
        if r["dim_lc"] < 45: faults.append(f"comment colour unreadable (ANSI8 Lc {r['dim_lc']:.0f})")
        if r["ring_min"] < 0.05: faults.append(f"bright ring collapses onto normal (dE {r['ring_min']:.3f})")
        if r["cvd_min"] < 0.10:
            worst = min(r["cvd"].items(), key=lambda kv: kv[1])
            faults.append(f"CVD collision on {worst[0]} (dE {worst[1]:.3f})")
        print(f"\n  {n}")
        print(f"    bg OKLCH hue {r['bg_hue']:5.1f} chroma {r['bg_chroma']:.3f} "
              f"(hue 30-90 = warm, 200-300 = cool)")
        if faults:
            for f in faults:
                print(f"    - {f}")
        else:
            print("    - no threshold violations")

    print("\n" + "=" * 100)
    print("ACHIEVABILITY — is 'all six chromatic normal slots >= Lc 60' met by anyone?")
    print("=" * 100)
    ok = [n for n, r in rows.items() if r["norm_min"] >= 60]
    print(f"  themes clearing it: {ok if ok else 'NONE'}")
    best = max(rows.items(), key=lambda kv: kv[1]["norm_min"])
    print(f"  best in field: {best[0]} at min Lc {best[1]['norm_min']:.1f}")
    warm = [n for n, r in rows.items() if 20 <= r["bg_hue"] <= 100]
    print(f"  warm-background themes (bg hue 20-100 deg): {warm if warm else 'NONE'}")


if __name__ == "__main__":
    main()
