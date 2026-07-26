# TerminalSpike — Step 0 gate harness

Throwaway spike answering the Step 0 gates in
[`../.afk/plans/native-swift-terminal-afk-host.md`](../.afk/plans/native-swift-terminal-afk-host.md).

**Question it exists to answer:** can SwiftTerm host `agent-afk`'s REPL correctly? afk's compositor
positions every line with absolute CUP escapes and never emits a newline
(`src/cli/cup-frame-renderer.ts:6-8`), which is an unusual and easy-to-get-subtly-wrong pattern.

Delete this whole directory once the gates are answered.

## Results (2026-07-26, SwiftTerm v1.15.0, Swift 6.4, macOS 27.0 arm64)

| Gate | What | Verdict |
|---|---|---|
| G1 | afk REPL paints, status line intact, no tearing | **PENDING — needs human** |
| G2 | Narrowing reflow produces no duplicate/orphan lines (SwiftTerm issue #494) | **PASS** (automated, 3 tests) |
| G3 | Shift+Tab cycles permission-mode ring | **PASS** (static analysis, certain) |
| G4 | Ctrl+B backgrounds a turn | **PENDING — needs human** |
| G5 | Bracketed paste mode tracked (afk requires `?2004h` + `200~`/`201~`) | **PASS** (automated) |
| G6 | Multi-hour soak, forced resizes, scrollback overflow, differential vs Ghostty | **PENDING — needs human** |

### G2 detail

Issue [#494](https://github.com/migueldeicaza/SwiftTerm/issues/494) ("Buffer reflow produces
duplicate/orphan lines when narrowing terminal") is **OPEN** and was the single biggest threat to the
project. Three headless tests narrow a terminal 80→40 cols and assert on token identity:

```
[G2-A before]             distinct tokens: 8,  duplicated: 0
[G2-A after]              distinct tokens: 7,  duplicated: 0    <- visible rows only
[G2-A after(full buffer)] distinct tokens: 8,  duplicated: 0    <- nothing orphaned
[G2-B before]             distinct tokens: 30, duplicated: 0
[G2-B after]              distinct tokens: 30, duplicated: 0
[G2-C before]             distinct tokens: 20, duplicated: 0
[G2-C after]              distinct tokens: 20, duplicated: 0
```

The 8→7 drop in G2-A's *visible* rows is legitimate scroll-off, not orphaning: rewrapping 8×100-char
lines from 16 rows to 24 rows overflows a 24-row screen once the cursor row is counted. The full-buffer
read confirms all 8 tokens survive with zero duplicates. G2-C is the afk-shaped case: DECSTBM scroll
region + absolute CUP addressing + no newlines, then resize.

**Caveat:** these are engine-level tests on synthetic content. They do **not** substitute for G6, the
multi-hour differential soak — #494's reporter describes an intermittent defect, and the paranoid
reading is that a single deterministic test can miss it.

### G3 detail — original risk assessment was WRONG

Planning flagged G3 as the top risk, claiming no `\x1b[Z` fallback existed. That was a grep error.
`Mac/MacTerminalView.swift` has **two** switches on the selector:

1. A kitty-protocol switch gated on `if !terminal.keyboardEnhancementFlags.isEmpty` (:1417).
   afk never enables the protocol, so this block is skipped entirely.
2. A plain-xterm fallback switch, which has
   `case #selector(insertBacktab(_:)): send(EscapeSequences.cmdBackTab)`.

And `EscapeSequences.swift:112`: `cmdBackTab: [UInt8] = [ 0x1b, 0x5b, 0x5a ]` — that is `ESC [ Z`,
i.e. CSI Z, exactly what afk's Node keypress parser needs to yield `{name:'tab', shift:true}`.

The original grep missed it because AppKit routes Shift+Tab to `insertBacktab(_:)` (lowercase `t`),
not `insertTab` with a shift modifier.

## Running it

Automated gates (G2, G5):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Human gates (G1, G3 live confirmation, G4, G6):

```sh
swift run TerminalSpike
```

then type `afk` in the window and work the checklist it prints. Geometry changes are logged to stderr
so a visual artifact can be correlated with the resize that produced it.

## Two local toolchain workarounds

Both are environmental, not project decisions. Neither affects gate validity.

1. **`vendor/SwiftTerm` is a patched copy of upstream v1.15.0.** Upstream declares
   `resources: [.process("Apple/Metal/Shaders.metal")]`, which invokes the `metal` compiler. Xcode 26.6
   moved the Metal toolchain to a separate downloadable component
   (`xcodebuild -downloadComponent MetalToolchain`) that is not installed here. The one-line patch
   excludes the shader instead. `MetalTerminalRenderer` probes for the shader bundle at runtime and
   returns nil when absent, so this compiles and the Core Text renderer is used. The gates exercise the
   VT **engine** (`Terminal.swift`/`Buffer.swift`), which is renderer-independent.

   `vendor/` is gitignored. To recreate: copy an upstream v1.15.0 checkout to `vendor/SwiftTerm`,
   `chmod -R u+w` it (SPM checkouts are read-only), then apply that one exclude change — it is
   annotated in place in `vendor/SwiftTerm/Package.swift`.

2. **`DEVELOPER_DIR` is needed for `swift test`.** `xcode-select -p` points at
   `/Library/Developer/CommandLineTools`, which does not ship the XCTest framework. Pointing
   `DEVELOPER_DIR` at the installed `/Applications/Xcode.app` for the single invocation avoids a
   system-wide `sudo xcode-select -s`. `swift build` and `swift run` work without it.

For the real project, prefer downloading the Metal toolchain (so the optional GPU renderer is
available) over carrying a vendored patch.
