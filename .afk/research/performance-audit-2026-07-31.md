# Performance audit — where Umber's time actually goes (2026-07-31)

Base: `main @ 0ebd717`. Vendored SwiftTerm = upstream v1.15.0 (`dd2fb8a`) + local patches 0001–0003.

Question asked: *are there any major performance improvements we should make?*

Short answer: **one major one, and it is already written and shipping — switched off by our own
patch.** Beyond that there is one small ungated debug loop in the vendored emulator that runs in
release builds, one main-thread filesystem hitch on window activation, and nothing else worth
touching. The byte-feed path — the thing you would normally suspect — is clean, and this document
says so explicitly so nobody spends a day there.

Everything below is either read from source with a citation or measured with a probe that is
reproduced inline. Where a claim is inferred rather than measured, it says so.

---

## 1. MAJOR — the vendored Metal GPU renderer exists, is complete, and is disabled by patch 0001

### What is actually there

Upstream v1.15.0 ships a full Metal renderer for macOS, not a stub:

- `vendor/SwiftTerm/Sources/SwiftTerm/Apple/Metal/MetalTerminalRenderer.swift` — 132 KB, ~2,800 lines,
  with a CoreText-rasterised glyph atlas (`GlyphAtlas.swift`), a buffer pool, and seven shader
  entry points.
- `Mac/MacTerminalView.swift:379` — `public func setUseMetal(_ enabled: Bool) throws`. A real,
  public, **throwing** API: it reports failure instead of trapping, so a call site can fall back.
- `Mac/MacTerminalView.swift:245` — `public var metalBufferingMode: MetalBufferingMode = .perRowPersistent`,
  documented as "caches per-row vertex data and only rebuilds dirty rows."

That last line is the whole point. It is precisely the cache the CPU path does not have.

### Why the CPU path is the ceiling

Per draw, for every row in the dirty range, the Core Text path rebuilds everything from scratch:

- `Apple/AppleTerminalView.swift:1364` — `buildAttributedString(row:line:cols:)` per row, per draw.
- `Apple/AppleTerminalView.swift:1400` — `CTLineCreateWithAttributedString` per segment, per row,
  per draw.
- There is **no per-row cache on macOS.** The `attrStrBuffer: CircularList<ViewLineInfo>` cache
  exists only in the iOS view (`iOS/iOSTerminalView.swift:237`). Grep for it under `Apple/` or
  `Mac/`: nothing.
- The per-line "skip rows that do not intersect the dirty rect" optimisation is present but
  **compiled out** — `Apple/AppleTerminalView.swift:1352-1362` is inside `#if false`, with
  upstream's own note that AppKit sends full exposes anyway.
- Damage is tracked as a **min/max span**, not a row set (`Terminal.swift:5035` `updateRange`,
  `:5107` `getUpdateRange`). One changed row near the top plus one near the bottom means every row
  between them is rebuilt.

Draws are throttled to 60 fps (`Apple/AppleTerminalView.swift:1912-1930`, `queuePendingDisplay`,
16.67 ms), with a deliberate bypass so local echo skips the throttle
(`Mac/MacTerminalView.swift:213`, a 150 ms `interactiveInputDisplayWindowNs`). So the cost is not
unbounded — it is bounded at *rebuild-the-visible-grid, sixty times a second*, on the CPU, with a
CoreText shaping pass per row each time.

### Why it is off, and why that reason no longer holds

`patches/swiftterm/0001-exclude-metal-shader-from-target.patch` replaces
`resources: [.process("Apple/Metal/Shaders.metal")]` with an `exclude:`. Its stated reason is
correct as far as it goes: Xcode 26.6 moved the Metal toolchain to a downloadable component, this
machine has Command Line Tools only, and `.process` on a `.metal` file invokes the offline compiler.

Falsified control, run 2026-07-31 in a throwaway package at `/tmp/copytest`:

```
.copy("Shaders.metal")    → Build complete! (17.82 sec)
                            .build/out/Products/Debug/CopyTest_CopyTest.bundle/Contents/Resources/Shaders.metal
.process("Shaders.metal") → error: unable to spawn process 'metal' (No such file or directory)
                            error: CompileMetalFile ... failed with a nonzero exit code
```

So `.process` is genuinely impossible here — and `.copy` is genuinely fine. `exclude` was one step
too far: it drops the shader from the bundle entirely, and the bundle is exactly where the renderer
looks for it.

`MetalTerminalRenderer.makeLibrary` (`Apple/Metal/MetalTerminalRenderer.swift:2746`) has a
three-tier fallback:

1. `device.makeDefaultLibrary()` — nothing, no `.metallib` was built.
2. `findMetallibURL()` (`:2808`) — nothing, same reason.
3. `loadShaderSource()` (`:2797`) → `device.makeLibrary(source:)` (`:2765`) — **compiles the `.metal`
   source at runtime**, which goes through the OS Metal compiler service and needs no offline
   toolchain at all.

With `exclude`, tier 3 cannot find the file either, so it throws `shaderSourceMissing` (`:2762`) and
the view silently stays on Core Text. That is the current state: `grep -rn "setUseMetal\|Metal"
app/Sources/Umber` returns exactly one hit, a comment in `UmberTerminalView.swift:12`. Umber has
never asked for the GPU path, and could not have got it if it had.

### Proof that tier 3 works on this machine

`/tmp/umber-metal-probe/probe.swift` — reads the real `Shaders.metal`, compiles it at runtime,
checks all seven required functions, and builds a real `MTLRenderPipelineState`:

```
device: Apple M4 Pro
makeDefaultLibrary(): nil  (expected — no metallib)
run 1: makeLibrary(source:) OK in 173.0 ms
run 2: makeLibrary(source:) OK in 0.0 ms
run 3: makeLibrary(source:) OK in 0.0 ms
PASS: all 7 required shader functions present
PASS: render pipeline state created from runtime-compiled library
```

173 ms cold, then free — the OS caches the compiled library across calls and processes. The cold
cost is paid inside `MetalTerminalRenderer.init`, i.e. once per terminal view created, and only on
the first one.

### The change, end to end

1. Rewrite patch `0001`: `exclude:` → `resources: [.copy("Apple/Metal/Shaders.metal")]`. Update the
   `Package.swift` hash in `patches/swiftterm/SwiftTerm.pin` and the patch's own comment (its
   current rationale becomes wrong, and a stale *why* is worse here than no comment).
2. `app/Scripts/make-app-bundle.sh:51-53` **already** copies `"$BIN_DIR"/*.bundle` into
   `Contents/Resources/`. That is one of the two locations `candidateBundles()`
   (`MetalTerminalRenderer.swift:2828`) probes, and the dev path (`swift run Umber`) is the other.
   No script change needed — the plumbing has been sitting there with nothing to carry.
3. In `TerminalPane`, `try? terminalView.setUseMetal(true)`, keyed off a config field so it can be
   turned off without a rebuild, and log the thrown error under `UMBER_DIAG`. The API throws rather
   than traps, so the fallback to Core Text is free and automatic.
4. `TerminalPane.swift` is 14 lines under the 350-LOC ceiling. This is the concern that gets its
   own file — `TerminalPane+Renderer.swift`.

### What is NOT proven, and the risk

I have not measured frames or throughput inside Umber, before or after. The claim "major" rests on
architecture (per-draw CoreText shaping with no cache, versus a glyph atlas with per-row persistent
vertex buffers), not on a number. **The magnitude is unmeasured.**

Upstream also labels it plainly: `Mac/MacTerminalView.swift:217` — *"Experimental GPU path: CoreText
glyph atlas + Metal quads. Limitations: image caching is basic; GPU path is still evolving."* In a
repo with no test target, turning on an experimental renderer without a gate is exactly the move
this project has already been burned by once (see the reflow gate's history in `AFK.md`).

So the deliverable is not the two-line patch. It is the gate: an offscreen harness in the shape of
`check-find-menu.sh` that builds a `LocalProcessTerminalView`, runs a large `cat` through a real
pty, and reports wall-clock and draw count — run once on Core Text and once on Metal. That single
number both sizes the win and becomes the check that keeps it honest, and it is the same
falsification discipline `check-reflow.sh` and `check-altbuffer-resize.sh` already encode.

---

## 2. SMALL, CHEAP, CERTAIN — an ungated debug loop runs in release, in `Buffer.resize`

`vendor/SwiftTerm/Sources/SwiftTerm/Buffer.swift:544-557`:

```swift
// DEBUG: Post-condition
if lines.count > 0 {
    for i in 0..<lines.count {
        let line = lines [i]
        if line.count < newCols {
            print ("stop here newCols=\(newCols) but the element has: \(line.count)")
            abort ()
        }
    }
}
```

It is **not** inside `#if DEBUG` — the file uses `#if DEBUG` correctly elsewhere (`:62`, `:81`,
`:98`, `:116`), which makes this one look like a leftover rather than a decision. Two consequences:

- **Cost.** It walks the whole buffer — viewport *plus* the entire scrollback (`lines.count`) — on
  every `Buffer.resize`. Every size change hits it: `processSizeChange`
  (`Apple/AppleTerminalView.swift:233` — live window drag, so *per drag frame*, ⌘B, full screen) and
  `resetFont` (`:151` — ⌘+/⌘-/⌘0, ⌘R). At the default 1000-line scrollback that is 1000 iterations
  per resize event per buffer. This is also the missing third walk behind `AFK.md`'s existing note
  that "`Buffer.resize` walks every line three times per window resize": walk 1 is `reflow`
  (`:522-524`), walk 2 is the narrowing trim patch `0003` added (`:538-543`), walk 3 is this.
- **Robustness.** `abort()` in a shipping app is a hard crash with no dialog and no save. Patch
  `0003` was written specifically because line widths and `cols` can disagree during resize; this
  loop turns a future variant of that class of bug into a crash rather than a glitch.

Fix: patch `0004`, wrapping the block in `#if DEBUG`. Two lines, no behaviour change in debug, and
it removes a release-build crash path. Same maintenance tax as every vendor patch — it must be
re-applied on upgrade and recorded in the pin, so it should ride along with the `0001` rewrite
rather than being a separate trip.

---

## 3. MINOR — the file tree re-reads the disk synchronously on every window activation

`app/Sources/Umber/FileTreeViewController.swift:123-140`. `refresh()` is called from
`SpaceViewController.windowDidBecomeKey()` (`:324-325`) and does, on the main thread:

- `root.reloadChildren()` → `FileManager.default.contentsOfDirectory` (`FileNode.swift:56`),
- a full `outlineView.reloadData()`,
- `expandItem` for every previously-expanded node, each of which lazily enumerates its own directory,
- then a linear scan over all rows to restore selection.

So the cost is O(expanded directories × entries) of synchronous filesystem work per activation, and
⌘-tabbing in and out of a Space pays it every time. On a shallow tree this is invisible; on a wide
`node_modules`-ish tree with several branches open it is a visible hitch on a window that has not
changed.

The file's own comment already names the upgrade ("FSEvents is the obvious upgrade if it ever feels
behind"). Cheaper interim fix: skip the refresh when nothing has changed — compare the root's
`contentModificationDate` (and each expanded node's) before rebuilding, which is one `stat` per
expanded directory instead of a full enumeration plus a reload.

Judgement: real, but it is a *hitch*, not a throughput problem. Do it after §1 and §2, or when it
is felt.

---

## 4. Checked and CLEAN — do not spend time here

Stated explicitly so this audit closes doors as well as opening them.

- **The pty read path.** `LocalProcess.swift:64` — `readSize = 128*1024`, via `DispatchIO` on a
  dedicated queue with `setLimit(highWater: readSize)` (`:438`, `:539`). A 128 KB read buffer is
  not the bottleneck; there is no per-1-KB main-thread hop to fix.
- **The parser.** Dispatch is a `switch` on a `UInt8`, not per-character closures, and there is a
  dedicated printable-ASCII run fast path — `Terminal.swift:1207`, `buffer.insertAsciiRun(data,
  attribute: curAttr)` — which skips the UTF-8 decode and column-width machinery entirely.
- **Draw coalescing.** Already correct, and already tuned for latency as well as throughput: 60 fps
  throttle plus a 150 ms post-keystroke bypass so echo does not wait for the next frame
  (`Apple/AppleTerminalView.swift:1912`, `:2160`; `Mac/MacTerminalView.swift:209-213`).
- **Attribute and colour caches.** `Mac/MacTerminalView.swift:292-300` — `attributes`,
  `urlAttributes`, a 256-slot `colors` array, `trueColors`. Attribute dictionaries are not rebuilt
  per cell.
- **The cwd poller.** `SpaceViewController+DirectoryFollow.swift` is a model of a cheap poller and
  needs no work: one timer per Space (not per pane), stopped on `windowDidResignKey` so a background
  Space costs nothing, two syscalls per tick, and a `lastPushed` pre-filter (`:57-62`) so an
  unchanged cwd never reaches AppKit. 1.33 ticks/sec while focused.
- **The document tab strip.** `mouseMoved` repaints only on an actual hover-state change
  (`DocumentTabStrip+Mouse.swift:48-57`). The per-draw `NSAttributedString` + `NSFont.systemFont`
  in `DocumentTabStrip+Drawing.swift:120-123` is a real allocation per tab per draw, but with ≤9
  tabs and repaints only on state change it is noise. `needsDisplay = true` invalidates the whole
  strip rather than a rect — also noise at this size.

---

## Recommended order

1. **§2 first** (patch `0004`, two lines): certain, tiny, removes a release-build `abort()`. No
   reason to sequence it behind anything.
2. **§1's gate before §1's switch**: build the offscreen throughput harness, get the Core Text
   baseline number. If Metal does not clearly beat it on this hardware, the recommendation dies
   cheaply and this document was still worth writing.
3. **§1's switch**, behind a config field, with `UMBER_DIAG` reporting which renderer is live.
4. **§3** when it is felt.

## Bearing on the libghostty probe

This does not settle `.afk/plans/emulator-foundation-probe-and-vendor-integrity.md`, but it does
re-price one of its inputs. Part of libghostty's appeal is a modern GPU renderer. It turns out the
incumbent has one too, sitting behind a one-line packaging mistake of our own making. Measuring
Core Text versus Metal *inside SwiftTerm* is a day's work and gives the probe a real baseline to
beat, instead of comparing a new GPU renderer against an old CPU one and attributing the whole
difference to the foundation.

## Not checked

- No profiler was run (no Instruments, no `sample`, no signposts). Every cost here is read from
  source or from the two probes quoted above.
- No before/after measurement of anything. Magnitudes are inferred; §1 says so at length.
- `MetalTerminalRenderer`'s own correctness (glyph coverage, ligatures, CJK/wide cells, selection,
  the "image caching is basic" caveat) was not reviewed. Upstream calls the path experimental and
  that has not been independently checked.
- Launch time, memory footprint, and per-Space cost at many open Spaces were not examined.
- `FileViewerPane` (the editor document) was not examined at all — a large-file open path is the
  obvious place a hitch would hide.

---

## Appendix — the runtime-shader probe, verbatim

Ephemeral when run (`/tmp/umber-metal-probe/probe.swift`), kept here so the §1 result is
reproducible without reconstructing it. Build and run **from the repo root**:
`swiftc -O probe.swift -o probe && ./probe` (or pass a shader path as argv[1]).

```swift
// Probe: can this machine compile SwiftTerm's Shaders.metal AT RUNTIME,
// with no offline Metal toolchain installed (xcrun metal is absent)?
//
// This is the load-bearing question behind "turn on the vendored Metal
// renderer": MetalTerminalRenderer.makeLibrary() falls back to
// device.makeLibrary(source:) when no .metallib is in the bundle
// (MetalTerminalRenderer.swift:2761-2769). Runtime compilation goes through
// the OS Metal compiler service, NOT through xcrun metal — so it should work
// even though `xcrun -sdk macosx metal --version` fails on this machine.
//
// Also times it, because makeLibrary runs inside MetalTerminalRenderer.init,
// i.e. once per terminal view created.

import Foundation
import Metal

// Repo-relative, and taken from argv when given, so this runs on any checkout. An
// absolute path here was the original spelling; it was scrubbed because AFK.md already
// names hardcoded /Users/... paths as a pre-public-release blocker class for this repo.
let defaultShaderPath = "vendor/SwiftTerm/Sources/SwiftTerm/Apple/Metal/Shaders.metal"
let shaderPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultShaderPath

let required = [
    "terminal_text_vertex",
    "terminal_cell_text_vertex",
    "terminal_text_fragment",
    "terminal_text_fragment_gray",
    "terminal_color_vertex",
    "terminal_cell_color_vertex",
    "terminal_color_fragment",
]

guard let device = MTLCreateSystemDefaultDevice() else {
    print("FAIL: MTLCreateSystemDefaultDevice() == nil (no Metal device)")
    exit(1)
}
print("device: \(device.name)")
print("lowPower: \(device.isLowPower)  unifiedMemory: \(device.hasUnifiedMemory)")

guard let source = try? String(contentsOfFile: shaderPath, encoding: .utf8) else {
    print("FAIL: cannot read \(shaderPath)")
    exit(2)
}
print("shader source bytes: \(source.utf8.count)")

// Does a default library already exist (it should not: no .metallib built)?
if let def = device.makeDefaultLibrary() {
    let have = required.allSatisfy { def.makeFunction(name: $0) != nil }
    print("makeDefaultLibrary(): present, hasRequiredFunctions=\(have)")
} else {
    print("makeDefaultLibrary(): nil  (expected — no metallib in this probe binary)")
}

// The real question: runtime source compilation.
var timings: [Double] = []
var lib: MTLLibrary?
for i in 0..<3 {
    let t0 = DispatchTime.now().uptimeNanoseconds
    do {
        let l = try device.makeLibrary(source: source, options: nil)
        let t1 = DispatchTime.now().uptimeNanoseconds
        let ms = Double(t1 - t0) / 1_000_000.0
        timings.append(ms)
        lib = l
        print(String(format: "run %d: makeLibrary(source:) OK in %.1f ms", i + 1, ms))
    } catch {
        print("FAIL run \(i + 1): makeLibrary(source:) threw: \(error)")
        exit(3)
    }
}

guard let library = lib else { exit(3) }

var missing: [String] = []
for name in required where library.makeFunction(name: name) == nil {
    missing.append(name)
}
if missing.isEmpty {
    print("PASS: all \(required.count) required shader functions present")
} else {
    print("FAIL: missing shader functions: \(missing.joined(separator: ", "))")
    exit(4)
}

// Can we actually build a render pipeline from them? (Pipeline creation is the
// next thing MetalTerminalRenderer.init does; a library that compiles but whose
// pipelines fail would be a false green.)
let desc = MTLRenderPipelineDescriptor()
desc.vertexFunction = library.makeFunction(name: "terminal_text_vertex")
desc.fragmentFunction = library.makeFunction(name: "terminal_text_fragment")
desc.colorAttachments[0].pixelFormat = .bgra8Unorm
desc.colorAttachments[0].isBlendingEnabled = true
do {
    _ = try device.makeRenderPipelineState(descriptor: desc)
    print("PASS: render pipeline state created from runtime-compiled library")
} catch {
    print("FAIL: makeRenderPipelineState threw: \(error)")
    exit(5)
}

let avg = timings.reduce(0, +) / Double(timings.count)
print(String(format: "runtime shader compile: avg %.1f ms over %d runs (paid once per MetalTerminalRenderer init)", avg, timings.count))
print("VERDICT: runtime Metal shader compilation WORKS on this machine without the offline Metal toolchain.")
```
