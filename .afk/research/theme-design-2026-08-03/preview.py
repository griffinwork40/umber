#!/usr/bin/env python3
"""
preview.py — render the candidates as an actual terminal, then LOOK at them.

The measurement suite answers "is it legible and colour-blind safe". It cannot
answer "is it beautiful", which is this project's stated bar. Four optimiser runs
each satisfied more constraints than the last while producing, in order: noise,
pastel, neon, and a green pinned at hue 157 (mint, not green). So the last gate is
visual, on realistic content: a git diff, ls output, an error, a prompt, dim text,
and the native sidebar the palette has to sit beside.

Emits preview.html. Open it, or screenshot it.

Run: python3 preview.py
"""

import json
from design_theme import oklch_to_hex, hex_to_oklch, apca_lc

FINAL = json.load(open("umber-palette.json"))

def variant(name, green_hue=None, magenta_hue=None, note=""):
    a = list(FINAL["ansi"])
    if green_hue is not None:
        L, C, _ = hex_to_oklch(a[2]);  a[2] = oklch_to_hex(L, C, green_hue)[0]
        L, C, _ = hex_to_oklch(a[10]); a[10] = oklch_to_hex(L, C, green_hue)[0]
    if magenta_hue is not None:
        L, C, _ = hex_to_oklch(a[5]);  a[5] = oklch_to_hex(L, C, magenta_hue)[0]
        L, C, _ = hex_to_oklch(a[13]); a[13] = oklch_to_hex(L, C, magenta_hue)[0]
    return dict(name=name, note=note, bg=FINAL["background"], fg=FINAL["foreground"],
                cursor=FINAL["cursor"], sel=FINAL["selection"], ansi=a)

CANDIDATES = [
    variant("Umber A — as searched", note="green hue 157 (pinned at bound): mint"),
    variant("Umber B — green pulled back", green_hue=146.0,
            note="green hue 146: recognisably green, costs red/green CVD margin"),
    variant("Umber C — green 150, magenta 335", green_hue=150.0, magenta_hue=335.0,
            note="compromise; magenta warmer, less lilac"),
]

REFERENCE = [
    dict(name="Tokyo Night (reference)", note="the v0.1 default", bg="#1A1B26",
         fg="#C0CAF5", cursor="#C0CAF5", sel="#283457",
         ansi=["#15161E", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7",
               "#7DCFFF", "#A9B1D6", "#414868", "#F7768E", "#9ECE6A", "#E0AF68",
               "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5"]),
    dict(name="afk-dark (reference)", note="Umber's current preset", bg="#0D1117",
         fg="#C9D1D9", cursor="#E67E4C", sel="#264F78",
         ansi=["#161B22", "#F85149", "#9CB04A", "#E5C07B", "#5BA8FF", "#9F7CE0",
               "#56B5A8", "#C9D1D9", "#484F58", "#F85149", "#A8E060", "#E67E4C",
               "#5BA8FF", "#F08AC4", "#5FE0C0", "#ECEFF4"]),
]


def term_block(t):
    a, bg, fg = t["ansi"], t["bg"], t["fg"]
    def s(i, txt, bold=False, bgc=None):
        st = f"color:{a[i]}"
        if bold: st += ";font-weight:600"
        if bgc: st += f";background:{bgc}"
        return f'<span style="{st}">{txt}</span>'
    dim = lambda txt: f'<span style="color:{a[8]}">{txt}</span>'

    lines = [
        f'{s(6,"~/Projects/umber")} {s(5,"on")} {s(3,"main")} {s(1,"[!2]")}',
        f'{s(2,"❯")} git status --short',
        f' {s(3,"M")} app/Sources/Umber/Theme.swift',
        f' {s(2,"A")} app/Scripts/check-theme-contrast.sh',
        f' {s(1,"D")} app/Sources/Umber/Legacy.swift',
        f'{s(5,"??")} .afk/research/theme-design/',
        "",
        f'{s(2,"❯")} git diff --stat',
        f' Theme.swift {dim("|")} {s(2,"18 +++++++++")}{s(1,"5 -----")}',
        f' Config.swift {dim("|")} {s(2,"3 ++")}{s(1,"1 -")}',
        "",
        f'{s(2,"❯")} swift build',
        f'{dim("[1/6] Compiling Umber Theme.swift")}',
        f'{dim("[4/6] Compiling Umber Config.swift")}',
        f'{s(1,"error:",True)} cannot find {s(3,"lightChromeCutoff")} in scope',
        f'  {dim("--> Config.swift:149:23")}',
        f'{s(3,"warning:",True)} unused variable {s(6,"luminance")}',
        f'{s(2,"✔ Build complete",True)} {dim("(2.41s)")}',
        "",
        f'{s(2,"❯")} ls',
        f'{s(4,"Scripts/",True)}  {s(4,"Sources/",True)}  {s(6,"Package.swift")}  '
        f'{s(2,"make-app.sh",True)}  {dim("README.md")}',
        "",
        f'{s(2,"❯")} echo selected text',
        f'<span style="background:{t["sel"]};color:{fg}">selected text renders here</span>',
        f'{s(2,"❯")} <span style="background:{t["cursor"]};color:{bg}">&nbsp;</span>',
    ]
    swatch = "".join(
        f'<div style="background:{c};width:26px;height:26px;display:inline-block;'
        f'border-radius:3px;margin:1px" title="{i}: {c}"></div>'
        + ("<br>" if i == 7 else "")
        for i, c in enumerate(a))
    return f'''
    <div class="card">
      <div class="hdr"><b>{t["name"]}</b><span class="note">{t["note"]}</span></div>
      <div class="win" style="background:{bg}">
        <div class="side">
          <div class="sh">UMBER &nbsp;<span style="opacity:.6">main +2</span></div>
          <div class="row">app</div>
          <div class="row" style="padding-left:18px;color:#E8A33D">Theme.swift &nbsp;M</div>
          <div class="row sel" style="padding-left:18px">Config.swift &nbsp;M</div>
          <div class="row" style="padding-left:18px;color:#41A85F">check-theme.sh &nbsp;A</div>
          <div class="row" style="opacity:.45">vendor</div>
        </div>
        <pre style="color:{fg}">{chr(10).join(lines)}</pre>
      </div>
      <div class="sw">{swatch}</div>
    </div>'''


HTML = f'''<!doctype html><meta charset="utf-8">
<style>
 body{{background:#6E6E73;font:13px -apple-system,BlinkMacSystemFont,sans-serif;
       margin:0;padding:22px}}
 .card{{margin-bottom:26px}}
 .hdr{{color:#fff;margin-bottom:7px;font-size:14px}}
 .note{{opacity:.72;margin-left:10px;font-size:12px}}
 .win{{display:flex;border-radius:9px;overflow:hidden;
       box-shadow:0 8px 26px rgba(0,0,0,.42);border:.5px solid rgba(255,255,255,.13)}}
 .side{{width:186px;flex:none;background:rgba(255,255,255,.055);
        border-right:.5px solid rgba(255,255,255,.10);padding:9px 0;
        color:#E8E8ED;font-size:11.5px}}
 .sh{{padding:3px 11px 8px;font-weight:600;font-size:10.5px;letter-spacing:.4px;
      opacity:.75}}
 .row{{padding:3px 11px}}
 .sel{{background:#0A63CE;color:#fff;border-radius:5px;margin:0 6px;padding-left:12px}}
 pre{{margin:0;padding:13px 16px;font:12.5px/1.62 "SF Mono",Menlo,monospace;
      flex:1;white-space:pre-wrap}}
 .sw{{margin-top:7px}}
</style>
<h2 style="color:#fff;margin:0 0 16px">Umber theme candidates — realistic content</h2>
{"".join(term_block(t) for t in CANDIDATES)}
<h2 style="color:#fff;margin:26px 0 16px">Reference</h2>
{"".join(term_block(t) for t in REFERENCE)}
'''

open("preview.html", "w").write(HTML)
print("wrote preview.html")
for t in CANDIDATES:
    print(f"\n{t['name']}")
    for i in (1, 2, 3, 4, 5, 6):
        L, C, H = hex_to_oklch(t["ansi"][i])
        print(f"   {i} {t['ansi'][i]}  OKLCH({L:.3f} {C:.3f} {H:5.1f})  "
              f"Lc {apca_lc(t['ansi'][i], t['bg']):5.1f}")
