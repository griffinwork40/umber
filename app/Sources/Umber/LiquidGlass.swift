//
//  LiquidGlass.swift
//  macOS 26+ Liquid Glass adoption — the single place all glass-specific code lives.
//
//  Umber gets Liquid Glass *automatically* when linked against the macOS 26 SDK:
//  the sidebar (via NSSplitViewItem) becomes a floating glass pane, window corners
//  round, controls gain glass bezels, and the menu bar goes transparent — all with
//  zero code changes. This file handles the enhancements that require explicit API
//  calls and cannot be automatic:
//
//  1. fullSizeContentView + transparent titlebar, so the sidebar and titlebar
//     merge into one continuous glass surface rather than sitting on an opaque
//     bar with glass applied to it.
//  2. NSGlassEffectView for floating panels (Command Palette, Symbol Outline),
//     replacing the older NSVisualEffectView(.hudWindow) material that predates
//     the glass system.
//
//  Everything here is guarded by @available(macOS 26, *). On macOS 14/15, these
//  helpers are never called, and the app renders exactly as it did before.
//
//  The terminal content area and the editor content area are NEVER touched by
//  glass — the ANSI colour contract, the 345-assertion contrast gate
//  (check-theme-contrast.sh), and SwiftTerm's opaque layer all require a known,
//  opaque background. Apple's own Terminal.app made the same call: glass chrome,
//  opaque content (MacForce review, September 2025).
//

import AppKit

/// macOS 26+ Liquid Glass helpers.
///
/// Called from three sites: `SpaceWindowController.init` (window chrome),
/// `CommandPalette.buildPanel`, and `SymbolOutlinePanel.init` (floating panels).
/// Keeping them here rather than inlining the `#available` blocks means a single
/// file to update when the glass API evolves — and a single file to read when
/// asking "what does Umber do differently on Tahoe?"
@available(macOS 26.0, *)
@MainActor
enum LiquidGlass {

    /// Enable Liquid Glass chrome on a Space window.
    ///
    /// Adds `.fullSizeContentView` so the sidebar extends behind the titlebar
    /// into one continuous glass surface, and makes the titlebar transparent so
    /// the glass renders through it rather than painting an opaque bar on top.
    ///
    /// On pre-26 systems fullSizeContentView was explicitly declined because the
    /// opaque titlebar hid the terminal's top ~1.7 rows — row 0, where the prompt
    /// and caret live (SpaceWindowController.swift:132-141). macOS 26 resolves
    /// this: NSSplitViewController propagates safe area insets to its split items,
    /// and DocumentAreaViewController.viewDidLayout() respects them via
    /// `view.safeAreaInsets.top`, so the document area sits *below* the glass
    /// titlebar rather than behind it.
    ///
    /// `window.backgroundColor` and `window.appearance` (set by the caller) are
    /// still honoured: the glass material samples the window background for
    /// tinting, so a dark-themed terminal gets a dark glass titlebar and a
    /// light-themed one gets light glass — matching the sidebar's own adaptive
    /// tint with no additional code.
    static func configureWindow(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        // The separator would draw a hard line through the glass surface where
        // the titlebar meets the content. With glass the boundary is the
        // material itself — a painted line contradicts it.
        window.titlebarSeparatorStyle = .none
    }

    /// Create a glass container for a floating panel (Command Palette,
    /// Symbol Outline).
    ///
    /// Replaces the `NSVisualEffectView(.hudWindow)` pattern used on pre-26
    /// systems. The glass material adapts to the content behind the panel and
    /// follows the system appearance, so it looks native in both light and dark
    /// mode without manual colour management.
    ///
    /// Callers add subviews to this view the same way they did to the old
    /// NSVisualEffectView — NSGlassEffectView is an NSView subclass and its
    /// `addSubview` works identically.
    static func makeGlassContainer(
        frame: NSRect,
        cornerRadius: CGFloat = 10
    ) -> NSView {
        let glass = NSGlassEffectView()
        glass.frame = frame
        glass.wantsLayer = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.masksToBounds = true
        glass.autoresizingMask = [.width, .height]
        return glass
    }
}
