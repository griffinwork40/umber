//
//  GitStatus+Presentation.swift
//  How a `GitFileStatus` looks in the sidebar: one colour, and one optional letter.
//
//  Its own file, rather than riding along in `FileTreeViewController+OutlineView.swift`,
//  because it extends a DIFFERENT type — exactly the argument
//  `DocumentStatus+Presentation.swift` makes for itself. `GitFileStatus` is declared in
//  `GitStatus.swift` and belongs to the parser, which must stay `Foundation`-only so
//  `check-git-status.sh` can compile it alone; the moment an `NSColor` appeared in that
//  file the gate would stop working. So the dependency runs one way only: the tree
//  renders the status enum, the status enum knows nothing about AppKit.
//
//  This is also the file that would grow if a second surface ever wants to show git
//  state — a tab-strip badge, a Space-level indicator — instead of that surface reaching
//  into the outline view's drawing code.
//

import AppKit

extension GitFileStatus {
    /// The row's tint, and the badge's.
    ///
    /// System colours, not hex literals, for the same three reasons the tab strip's dot
    /// uses them (`DocumentStatus.dotColour`): they adapt to Increase Contrast, they
    /// follow the window's effective appearance, and they keep this app's chrome derived
    /// rather than hardcoded. VS Code's own `gitDecoration.*` defaults were deliberately
    /// **not** copied — the hex values circulating for them are unverified third-party
    /// transcriptions, and pasting six magic numbers to imitate another app's dark theme
    /// would look wrong in light mode and wrong again under Increase Contrast.
    ///
    /// The ANSI palette was also considered and refused. At `theme == nil` — the default
    /// — no palette is installed at all, so there would be nothing to read; and once a
    /// theme *is* set, SwiftTerm regenerates ANSI 16–255 by interpolating the user's
    /// bg/fg (`AppConfig.theme`'s note), so a "green" sourced from it is not reliably
    /// green. Sidebar chrome is not terminal content and should not borrow its colours.
    ///
    /// The semantic mapping follows VS Code's *tokens* (which are stable and documented)
    /// rather than its pixels: modified is warm, new-content is green, gone-or-broken is
    /// red, ignored recedes.
    var decorationColour: NSColor {
        switch self {
        case .modified, .typeChanged:
            // Warm rather than green: a modified file is the one state that is neither
            // good news nor bad, and orange is the platform's "in progress" weight.
            // Type-changed shares it because a mode/symlink flip *is* a modification —
            // it earns its own letter (T) but not its own colour.
            return .systemOrange
        case .added, .renamed, .copied, .untracked:
            // All four are "content that is new here", which is what VS Code's green
            // family means. Untracked shares it deliberately: to a reader scanning the
            // tree, "new file" and "new staged file" are the same category, and the
            // letters (U vs A) carry the distinction for anyone who needs it.
            return .systemGreen
        case .deleted:
            return .systemRed
        case .conflicted:
            // Distinct from `.deleted`'s red on purpose. A conflict is the one state
            // where continuing to work without noticing destroys information, so it must
            // not be confusable with the merely-removed — and `.systemPink` is the
            // platform colour closest to the pink-red VS Code reserves for it.
            return .systemPink
        case .ignored:
            // A label colour, not a grey literal: ignored rows should recede to whatever
            // "de-emphasised text" means in the current appearance, which is precisely
            // what the tertiary label role is defined as.
            return .tertiaryLabelColor
        }
    }

    /// What VoiceOver says instead of the badge letter.
    ///
    /// The letter and the colour are both glance affordances, and neither survives being
    /// read aloud: "M" is not a word and a tint is not announced at all. Without this the
    /// entire feature is invisible to a screen reader — which would make colour the *only*
    /// channel carrying the status, and colour alone is also what a colour-blind user does
    /// not get. That is the same reasoning that keeps the letter badge on by default rather
    /// than following Zed's colour-only look.
    var accessibilityDescription: String {
        switch self {
        case .conflicted: return "conflicted"
        case .added: return "added"
        case .modified: return "modified"
        case .deleted: return "deleted"
        case .renamed: return "renamed"
        case .copied: return "copied"
        case .typeChanged: return "type changed"
        case .untracked: return "untracked"
        case .ignored: return "ignored"
        }
    }
}

extension GitFileEntry {
    /// The row's status in words — the two facts a one-letter badge structurally cannot
    /// carry, joined to the one it can.
    ///
    /// `GitFileStatus.accessibilityDescription` above answers for the *status*; this
    /// answers for the whole *entry*, which is where `isStaged` (`GitStatus.swift:105`)
    /// and `originalPath` (`:107`) live. Both were parsed from the day the feature landed
    /// and neither reached a user: the badge column holds one character, and a rename
    /// source is a path. So they surface here instead, in the two channels that have room
    /// for a sentence — the tooltip and VoiceOver — rather than being encoded into more
    /// glyph vocabulary the reader would have to learn.
    ///
    /// Staged-ness is deliberately a *qualifier*, not a separate status. The parser
    /// already collapses X and Y to the more urgent of the two (`GitStatus.swift:281-287`,
    /// which prefers the worktree change because it is the one not yet recorded), so
    /// "modified, staged" is the honest reading of `XY = MM`: the worktree edit is what
    /// you see, and the index also holds one.
    var statusPhrase: String {
        var phrase = status.accessibilityDescription
        // Appended rather than prefixed: a screen-reader listener hears the noun they were
        // scanning for first, and the qualifier only matters once they have it.
        if isStaged { phrase += ", staged" }
        // Only rename and copy records carry an origin (`GitStatus.swift:213-222`), so this
        // is nil for every other status and costs nothing to ask.
        if let originalPath { phrase += ", from \(originalPath)" }
        return phrase
    }

    /// The same sentence, capitalised for a tooltip.
    ///
    /// Tooltips are read as prose and VoiceOver labels are read as a continuation of the
    /// filename, so only the case differs — one string, two presentations, rather than two
    /// strings that can drift. Only the first character is touched: `localizedCapitalized`
    /// would title-case the path in `from Sources/Umber/Old.swift` and misreport a filename.
    var tooltip: String {
        statusPhrase.prefix(1).uppercased() + statusPhrase.dropFirst()
    }
}
