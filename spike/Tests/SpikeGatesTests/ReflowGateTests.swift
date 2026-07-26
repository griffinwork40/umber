// Automated Step 0 gates. See ../../.afk/plans/native-swift-terminal-afk-host.md
//
// G2 — SwiftTerm issue #494 "Buffer reflow produces duplicate/orphan lines when
//      narrowing terminal" (OPEN, created 2026-03-20, untouched since 2026-03-29).
//      This is the single biggest technical threat to the project: it hits exactly
//      the code path agent-afk exercises (absolute-CUP compositor + window resize).
//
// G5 — bracketed paste mode tracking (afk REQUIRES ?2004h and parses 200~/201~).
//
// These run headless: a Terminal + delegate with NO process attached, fed bytes
// directly, so results are deterministic and repeatable.

import XCTest
import SwiftTerm

final class ReflowGateTests: XCTestCase {

    // MARK: helpers

    /// A headless terminal with no process started. `HeadlessTerminal` is itself a
    /// full `TerminalDelegate`, so this gives us a real engine with zero ceremony.
    private func makeTerminal(cols: Int, rows: Int, scrollback: Int = 500) -> HeadlessTerminal {
        HeadlessTerminal(
            options: TerminalOptions(cols: cols, rows: rows, scrollback: scrollback)
        ) { _ in }
    }

    /// Text of the currently visible rows.
    private func visibleText(_ terminal: Terminal) -> [String] {
        (0..<terminal.rows).compactMap {
            terminal.getLine(row: $0)?.translateToString(trimRight: true)
        }
    }

    /// Whole normal buffer (should include scrollback), as text.
    private func normalBufferText(_ terminal: Terminal) -> String {
        let data = terminal.getBufferAsData(kind: .normal)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Count occurrences of each `TOKnnnn` marker.
    private func tokenCounts(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        let pattern = try! NSRegularExpression(pattern: "TOK[0-9]{4}")
        let ns = text as NSString
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tok = ns.substring(with: m.range)
            counts[tok, default: 0] += 1
        }
        return counts
    }

    /// A uniquely-tokenized line long enough to wrap at `cols`.
    private func wrappingLine(_ index: Int, width: Int) -> String {
        let token = String(format: "TOK%04d", index)
        let filler = String(repeating: "x", count: max(0, width - token.count))
        return token + filler
    }

    private func report(_ label: String, _ counts: [String: Int]) {
        let dupes = counts.filter { $0.value > 1 }.sorted { $0.key < $1.key }
        print("[\(label)] distinct tokens: \(counts.count), duplicated: \(dupes.count)")
        for (tok, n) in dupes.prefix(10) {
            print("[\(label)]   DUPLICATE \(tok) x\(n)")
        }
    }

    // MARK: - sanity

    /// If this fails, nothing else in this file means anything.
    func testFeedAndReadBackWorks() {
        let h = makeTerminal(cols: 80, rows: 10)
        h.terminal.feed(text: "TOK0001hello\r\n")
        let text = visibleText(h.terminal).joined(separator: "\n")
        XCTAssertTrue(text.contains("TOK0001hello"), "basic feed/read-back broken; got:\n\(text)")
    }

    // MARK: - G2

    /// G2-A: narrowing reflow with everything on screen (no scroll-off).
    /// 8 wrapped lines at 80 cols (16 rows) -> 40 cols (24 rows), fits in 24 rows.
    /// Every token must still appear exactly once.
    func testG2A_NarrowingReflowOnScreenProducesNoDuplicates() {
        let h = makeTerminal(cols: 80, rows: 24)
        for i in 1...8 {
            h.terminal.feed(text: wrappingLine(i, width: 100) + "\r\n")
        }

        let before = tokenCounts(in: visibleText(h.terminal).joined(separator: "\n"))
        report("G2-A before", before)

        h.terminal.resize(cols: 40, rows: 24)

        let after = tokenCounts(in: visibleText(h.terminal).joined(separator: "\n"))
        report("G2-A after", after)

        let duplicated = after.filter { $0.value > 1 }
        XCTAssertTrue(
            duplicated.isEmpty,
            "G2-A FAIL: reflow duplicated tokens after narrowing 80->40: \(duplicated.sorted { $0.key < $1.key })"
        )

        // Issue #494 is "duplicate/ORPHAN lines" — so absence of duplicates is only
        // half the gate. The visible-rows read above can legitimately show fewer
        // tokens once reflow pushes content into scrollback (8 lines x 100 chars
        // rewraps from 16 rows to 24 rows, which overflows a 24-row screen once the
        // cursor row is counted). Assert against the FULL normal buffer so a genuine
        // orphaned/dropped line cannot hide behind that explanation.
        let full = tokenCounts(in: normalBufferText(h.terminal))
        report("G2-A after(full buffer)", full)
        let missing = (1...8)
            .map { String(format: "TOK%04d", $0) }
            .filter { (full[$0] ?? 0) == 0 }
        XCTAssertTrue(
            missing.isEmpty,
            "G2-A FAIL: reflow ORPHANED tokens (present before, absent from full buffer after): \(missing)"
        )
        let fullDuplicated = full.filter { $0.value > 1 }
        XCTAssertTrue(
            fullDuplicated.isEmpty,
            "G2-A FAIL: full-buffer duplicates after narrowing: \(fullDuplicated.sorted { $0.key < $1.key })"
        )
    }

    /// G2-B: narrowing reflow with scrollback pressure — the shape issue #494 describes.
    /// Duplicates are unambiguous corruption. Missing tokens are NOT asserted on,
    /// because legitimate scrollback trimming can drop lines.
    func testG2B_NarrowingReflowWithScrollbackProducesNoDuplicates() {
        let h = makeTerminal(cols: 80, rows: 10, scrollback: 500)
        for i in 1...30 {
            h.terminal.feed(text: wrappingLine(i, width: 100) + "\r\n")
        }

        let before = tokenCounts(in: normalBufferText(h.terminal))
        report("G2-B before", before)

        h.terminal.resize(cols: 40, rows: 10)

        let after = tokenCounts(in: normalBufferText(h.terminal))
        report("G2-B after", after)

        let duplicated = after.filter { $0.value > 1 }
        XCTAssertTrue(
            duplicated.isEmpty,
            "G2-B FAIL: reflow duplicated tokens with scrollback present: \(duplicated.sorted { $0.key < $1.key })"
        )
    }

    /// G2-C: the afk-shaped pattern. DECSTBM scroll region + absolute CUP addressing,
    /// never emitting a newline, then resize. This is precisely what
    /// src/cli/cup-frame-renderer.ts does ("no \n is ever emitted").
    func testG2C_ScrollRegionPlusAbsoluteCUPSurvivesNarrowing() {
        let h = makeTerminal(cols: 80, rows: 24)

        // DECSTBM: scroll region rows 1..20
        h.terminal.feed(text: "\u{1b}[1;20r")

        // Paint rows 1..20 by absolute positioning only. No newlines.
        for row in 1...20 {
            h.terminal.feed(text: "\u{1b}[\(row);1H" + String(format: "TOK%04d", row))
        }

        let before = tokenCounts(in: visibleText(h.terminal).joined(separator: "\n"))
        report("G2-C before", before)
        XCTAssertEqual(before.count, 20, "G2-C setup: expected 20 painted tokens, got \(before.count)")

        h.terminal.resize(cols: 40, rows: 24)

        let after = tokenCounts(in: visibleText(h.terminal).joined(separator: "\n"))
        report("G2-C after", after)

        let duplicated = after.filter { $0.value > 1 }
        XCTAssertTrue(
            duplicated.isEmpty,
            "G2-C FAIL: scroll-region + CUP content duplicated on narrowing: \(duplicated.sorted { $0.key < $1.key })"
        )
    }

    // MARK: - G5

    /// G5: afk enables ?2004h and parses 200~/201~. The core must track the mode,
    /// because Mac/MacTerminalView.swift:1543-1592 keys paste-wrapping off it.
    /// (Note: the `// TODO: must implement bracketed paste mode` at
    /// Terminal.swift:4458 is stale — the view layer does implement it.)
    func testG5_BracketedPasteModeIsTracked() {
        let h = makeTerminal(cols: 80, rows: 10)

        XCTAssertFalse(h.terminal.bracketedPasteMode, "should start disabled")

        h.terminal.feed(text: "\u{1b}[?2004h")
        XCTAssertTrue(h.terminal.bracketedPasteMode, "G5 FAIL: ?2004h did not enable bracketed paste")

        h.terminal.feed(text: "\u{1b}[?2004l")
        XCTAssertFalse(h.terminal.bracketedPasteMode, "G5 FAIL: ?2004l did not disable bracketed paste")
    }
}
