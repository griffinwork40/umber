//
//  SidebarToggleAccessory.swift
//  The discoverable button beside the traffic lights that toggles the sidebar.
//
//  ⌘B and View → Toggle Sidebar already worked — both drive
//  `NSSplitViewController.toggleSidebar(_:)` through the responder chain
//  (`AppMenu.swift:205-207`) — but neither is discoverable without already
//  knowing the app has a sidebar to hide, or that this app even has a menu bar
//  shortcut for it. This is the click target: one borderless SF Symbol button,
//  wired to the exact same selector the menu item uses, so it inherits the
//  same enablement and the same collapse animation for free instead of
//  reimplementing either.
//
//  `NSTitlebarAccessoryViewController` rather than a custom titlebar view: it
//  is the system affordance for adding a control beside the traffic lights.
//  `SpaceWindowController` declines `.fullSizeContentView`
//  (`SpaceWindowController.swift:168` and the comment above it) precisely so
//  the titlebar stays an opaque strip AppKit owns and draws — this accessory
//  attaches to that strip rather than requiring any change to it.
//
//  `target = nil`. Same reasoning as the menu item: the responder chain finds
//  `SpaceViewController`, the window's `contentViewController`, which
//  inherits the selector from `NSSplitViewController` — so this button and
//  the menu item are two doors onto the one piece of state
//  (`NSSplitViewItem.isCollapsed`), never a second copy of it.
//

import AppKit

/// One borderless button, permanently installed on the leading edge of every
/// Space window's titlebar.
///
/// No stored state beyond the button itself: there is nothing here to read
/// back later, so `SpaceWindowController` constructs one and hands it straight
/// to `NSWindow.addTitlebarAccessoryViewController(_:)` without keeping a
/// reference — the window retains its own accessory list.
@MainActor
final class SidebarToggleAccessory: NSTitlebarAccessoryViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        // `.left`, not the semantically tempting `.leading`: AppKit documents
        // only `.left`, `.right`, and `.bottom` as valid titlebar-accessory
        // positions; every other NSLayoutConstraint attribute raises an
        // assertion. Left puts the control beside both the traffic lights and
        // the sidebar it controls.
        layoutAttribute = .left
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — controllers are created programmatically")
    }

    override func loadView() {
        // Keep the accessory's root a plain, zero-inset view. An NSButton has
        // alignment-rect insets; making it the root lets AppKit's titlebar
        // constraints move its frame origin, which the accessory controller
        // explicitly forbids ("changing the view's origin is not allowed").
        // The container owns the 28×24 titlebar footprint while Auto Layout
        // centres the button inside it without moving the accessory itself.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        // SF Symbol, not a bespoke glyph: `sidebar.leading` is the system
        // symbol Finder, Xcode and Safari all use for this exact control, so
        // it reads as "toggle sidebar" with no label needed. Template mode is
        // what lets it re-tint itself for light/dark and for every theme's
        // window appearance — same reasoning as the git branch glyph
        // (`GitBranchHeaderView.swift:51-54`).
        button.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.image?.isTemplate = true
        // Borderless, image-only: no local `NSButton` precedent exists
        // anywhere in this codebase to match, so this defaults to the system
        // idiom for a titlebar icon button rather than a bespoke bezel.
        button.isBordered = false
        button.imagePosition = .imageOnly
        // No target: the same responder-chain trick as the menu item
        // (`AppMenu.swift:201-207`) — `SpaceViewController` inherits
        // `toggleSidebar(_:)` from `NSSplitViewController`, so this button
        // and ⌘B drive the identical state through the identical selector,
        // never a second implementation of "hide the sidebar".
        button.target = nil
        button.action = #selector(NSSplitViewController.toggleSidebar(_:))
        // A tooltip and an accessibility label say what the glyph alone
        // cannot, mirroring `GitBranchHeaderView.swift:106-108` and the row
        // tooltip in `FileTreeViewController+OutlineView.swift:178` — a
        // control with only a glyph is unlabelled on hover and unusable by
        // VoiceOver without both.
        button.setAccessibilityLabel("Toggle Sidebar")
        button.toolTip = "Toggle Sidebar"

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        view = container
    }
}
