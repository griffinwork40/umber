//
//  DocumentTabStrip.swift
//  The in-window document tabs. Hand-rolled, on purpose.
//
//  Native macOS window tabs are KEPT by this design — they were promoted to mean
//  *Spaces* (projects), which is where drag-out-to-detach and Merge All Windows
//  actually mean something (plan §12.3, branch C). They cannot also serve
//  documents: a window tab is an NSWindow, so a mixed terminal/editor strip would
//  put each document in its own window and there could be no shared sidebar
//  (plan §12.2). Hence this strip — the one piece of chrome (C) pays to hand-roll.
//
//  Drawn in a single view with rect hit-testing rather than assembled from
//  per-tab NSButton/NSTextField subviews. Fewer moving parts, no subview
//  teardown churn on every title change (the shell repaints titles constantly via
//  OSC 0/2), and exact control of the one visual trick that makes a flat strip
//  read correctly: the active tab is painted in the *terminal's* background colour
//  so it merges with the content below it, while inactive tabs sit on a slightly
//  contrasted rail.
//

import AppKit

@MainActor
protocol DocumentTabStripDelegate: AnyObject {
    func tabStrip(_ strip: DocumentTabStrip, didSelect index: Int)
    func tabStrip(_ strip: DocumentTabStrip, didRequestClose index: Int)
    func tabStripDidRequestNewDocument(_ strip: DocumentTabStrip)
}

@MainActor
final class DocumentTabStrip: NSView {
    struct Item {
        let title: String
        let symbolName: String
        /// Unsaved changes. Drawn as a dot where the × would go — see `draw`.
        var isEdited: Bool = false
    }

    /// Matches the visual weight of a Safari/Ghostty tab rail. Anything taller
    /// starts stealing rows from the terminal, which is the primary surface.
    static let height: CGFloat = 30

    /// Hard floor on a tab's width, and the reason the strip can be laid out at all
    /// at high document counts. It was 96 — a *comfort* number that read well but
    /// was applied as a floor with no escape hatch, so past ~8 documents on a normal
    /// window `tabRect` handed out x positions beyond `bounds.width`: those tabs (and
    /// the "+" at `count * tabWidth`) were drawn and hit-tested off the right edge and
    /// were unreachable by mouse, ⌘1–9 being the only way to select them.
    ///
    /// 56 is derived from `drawTab`, not picked: padding 8 + symbol 12 + gap 5 +
    /// close box 15 + padding 8 = 48pt of fixed furniture, so 56 keeps the icon and
    /// the close/edited box intact and merely elides the title (`drawTab` already
    /// declines to draw text when the reserved span collapses — see the
    /// `textRight > textLeft` guard). Below that a tab is not a tab, so anything that
    /// does not fit at 56 moves into the overflow menu instead of being squeezed
    /// into an unclickable sliver.
    private static let minTabWidth: CGFloat = 56
    private static let maxTabWidth: CGFloat = 210
    private static let newButtonWidth: CGFloat = 30
    /// The chevron that opens the full document list. Narrower than the "+" because
    /// it is a fallback affordance, not one you reach for every few minutes.
    private static let overflowButtonWidth: CGFloat = 24
    private static let closeBoxSide: CGFloat = 15
    private static let horizontalPadding: CGFloat = 8

    weak var delegate: DocumentTabStripDelegate?

    private var items: [Item] = []
    private var activeIndex: Int = 0
    private var hoveredTab: Int?
    private var hoveredClose: Int?
    private var isHoveringNewButton = false
    private var isHoveringOverflowButton = false

    /// Colours are pushed in from the resolved config rather than read from a
    /// global: a nil theme leaves SwiftTerm on its own defaults (black), and the
    /// strip has to agree with whatever the terminal actually rendered or the two
    /// halves of the window visibly disagree — the same reasoning as
    /// `SpaceWindowController`'s window `backgroundColor`.
    private var contentBackground: NSColor = .black
    private var contentForeground: NSColor = .white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — views are created programmatically")
    }

    // MARK: - Input from the owner

    func apply(background: NSColor, foreground: NSColor) {
        contentBackground = background
        contentForeground = foreground
        needsDisplay = true
    }

    func reload(items: [Item], activeIndex: Int) {
        self.items = items
        self.activeIndex = activeIndex
        needsDisplay = true
    }

    // MARK: - Geometry
    //
    // One source of truth for the layout, consumed by both drawing and hit
    // testing. Two independent copies of this arithmetic is how a strip ends up
    // closing the tab next to the one you clicked.
    //
    // That invariant is now *structural*: everything geometric derives from a single
    // `Layout` value, so the visible window cannot be computed one way for `draw`
    // and another way for `mouseDown`.
    //
    // Strategy for more documents than fit: compress to a 56pt floor, then window
    // the strip and put the whole document list behind an overflow chevron.
    //   - Compress first because it is free and covers the common case: a
    //     1200pt window fits 20 tabs at the floor, so most people never see the
    //     chevron at all.
    //   - Window (rather than pan/scroll) because the window is *derived from
    //     `activeIndex`* and needs no stored scroll offset — one less piece of state
    //     to get stale against `reload`, and it makes ⌘1–9 / ⌘⇧[ ] scroll the strip
    //     for free: selecting a document always brings it into view.
    //   - Overflow *menu* rather than trackpad scrolling as the escape hatch,
    //     because a menu is the affordance that is guaranteed reachable — it is
    //     pinned to the right edge, keyboard- and VoiceOver-navigable, and lists
    //     every document including the ones the window is not showing. Trackpad
    //     scrolling would leave a mouse-only user with no visible way to reach a
    //     tab, which is the exact bug being fixed.
    //
    // Layout is strictly left-to-right and always ends at `bounds.maxX`:
    // [visible tabs][overflow chevron, if overflowing][+]. Nothing is ever placed
    // past the right edge, which is what the pre-fix `CGFloat(index) * tabWidth`
    // and `CGFloat(items.count) * tabWidth` both did once `tabWidth` hit its floor.

    /// A resolved layout for the current `bounds`, `items` and `activeIndex`.
    /// Purely derived — no stored scroll state to fall out of sync.
    private struct Layout {
        let tabWidth: CGFloat
        /// Absolute item indices drawn, left to right. Always contains `activeIndex`
        /// when `items` is non-empty.
        let visible: Range<Int>
        /// True when `visible` is a strict subset of `items.indices`, i.e. the
        /// chevron is present and consuming width.
        let isOverflowing: Bool
    }

    private var layout: Layout {
        guard !items.isEmpty else {
            return Layout(tabWidth: 0, visible: 0..<0, isOverflowing: false)
        }

        // The "+" is never sacrificed: it is the only way to open a document with
        // the mouse, so its width comes off the top before tabs get any.
        let withoutNewButton = max(bounds.width - Self.newButtonWidth, 0)
        let fitsAtFloor = Int(withoutNewButton / Self.minTabWidth)

        if items.count <= fitsAtFloor {
            // Everything fits: divide evenly, clamped as before. `maxTabWidth` is
            // what leaves the "+" adjacent to the last tab instead of stranded at
            // the far edge of a wide window.
            let even = withoutNewButton / CGFloat(items.count)
            let width = min(max(even, Self.minTabWidth), Self.maxTabWidth)
            return Layout(tabWidth: width, visible: items.indices, isOverflowing: false)
        }

        let forTabs = max(bounds.width - Self.newButtonWidth - Self.overflowButtonWidth, 0)
        // `max(_, 1)` so a window too narrow for even one floor-width tab still
        // draws one (degenerate, sub-floor) tab rather than dividing by zero. The
        // chevron stays reachable in that state, so no document is lost.
        let count = max(Int(forTabs / Self.minTabWidth), 1)
        let width = min(forTabs / CGFloat(count), Self.maxTabWidth)

        // Slide the window just far enough to contain the active tab. Anchoring on
        // the selection is why no scroll offset has to be stored or invalidated.
        var first = min(max(activeIndex - count + 1, 0), max(items.count - count, 0))
        if activeIndex < first { first = activeIndex }
        let upper = min(first + count, items.count)
        return Layout(tabWidth: width, visible: first..<upper, isOverflowing: true)
    }

    /// Rect for an absolute item index, or `nil` when the windowed strip is not
    /// showing that index. Returning `nil` rather than an off-screen rect is what
    /// keeps drawing and hit-testing honest about which tabs exist on screen.
    private func tabRect(_ index: Int, _ layout: Layout) -> NSRect? {
        guard layout.visible.contains(index) else { return nil }
        let slot = CGFloat(index - layout.visible.lowerBound)
        return NSRect(x: slot * layout.tabWidth, y: 0, width: layout.tabWidth, height: bounds.height)
    }

    private func closeRect(_ tab: NSRect) -> NSRect {
        NSRect(
            x: tab.maxX - Self.horizontalPadding - Self.closeBoxSide,
            y: (tab.height - Self.closeBoxSide) / 2,
            width: Self.closeBoxSide,
            height: Self.closeBoxSide
        )
    }

    /// Pinned to the right edge, immediately left of the "+". Both buttons are
    /// measured back from `bounds.maxX` so neither can be pushed off by tab count.
    private func overflowButtonRect(_ layout: Layout) -> NSRect? {
        guard layout.isOverflowing else { return nil }
        return NSRect(
            x: bounds.maxX - Self.newButtonWidth - Self.overflowButtonWidth, y: 0,
            width: Self.overflowButtonWidth, height: bounds.height
        )
    }

    private func newButtonRect(_ layout: Layout) -> NSRect {
        // When overflowing, the tabs plus the chevron consume exactly the width up
        // to `bounds.maxX - newButtonWidth`, so both branches agree; the explicit
        // right-edge anchor is the guarantee, not the coincidence.
        let x =
            layout.isOverflowing
            ? bounds.maxX - Self.newButtonWidth
            : min(
                CGFloat(layout.visible.count) * layout.tabWidth,
                max(bounds.maxX - Self.newButtonWidth, 0))
        return NSRect(x: x, y: 0, width: Self.newButtonWidth, height: bounds.height)
    }

    private func tabIndex(at point: NSPoint, _ layout: Layout) -> Int? {
        guard layout.tabWidth > 0, point.x >= 0 else { return nil }
        let slot = Int(point.x / layout.tabWidth)
        guard slot >= 0, slot < layout.visible.count else { return nil }
        let index = layout.visible.lowerBound + slot
        return items.indices.contains(index) ? index : nil
    }

    // MARK: - Drawing

    /// Perceptual darkness of the terminal background, used to decide which way to
    /// push the rail and the inactive text. Falls back to "dark" because a nil
    /// theme means SwiftTerm's defaults, whose background is black
    /// (`Colors.swift:37` defaultBackground).
    private var contentIsDark: Bool {
        guard let rgb = contentBackground.usingColorSpace(.deviceRGB) else { return true }
        return rgb.brightnessComponent < 0.5
    }

    private var railBackground: NSColor {
        let toward: NSColor = contentIsDark ? .white : .black
        // Small fraction on purpose: the rail should read as a shade of the
        // terminal, not as a separate piece of system chrome bolted on top.
        return contentBackground.blended(withFraction: 0.07, of: toward) ?? contentBackground
    }

    private var hoverBackground: NSColor {
        let toward: NSColor = contentIsDark ? .white : .black
        return contentBackground.blended(withFraction: 0.13, of: toward) ?? contentBackground
    }

    override func draw(_ dirtyRect: NSRect) {
        railBackground.setFill()
        bounds.fill()

        // Resolve once per paint and pass it down: recomputing `layout` per tab would
        // be correct but would re-derive the window N times for no reason, and it is
        // the same value that hit-testing will use.
        let layout = self.layout
        for index in layout.visible {
            drawTab(index, layout)
        }
        if let overflow = overflowButtonRect(layout) {
            drawOverflowButton(in: overflow)
        }
        drawNewButton(layout)

        // Hairline under the *inactive* stretch only. Running it under the active
        // tab too would draw a line between the tab and its own content, which is
        // precisely the seam this design removes.
        contentForeground.withAlphaComponent(0.12).setFill()
        let hairline = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        // `?? .zero` covers the active tab having been windowed out; `slices` treats
        // an empty exclusion as "no exclusion", so the hairline simply runs the full
        // width — correct, because in that state no tab on screen owns the content.
        let active = tabRect(activeIndex, layout) ?? .zero
        for slice in hairline.slices(excluding: active) {
            slice.fill()
        }
    }

    private func drawTab(_ index: Int, _ layout: Layout) {
        guard let rect = tabRect(index, layout) else { return }
        let isActive = index == activeIndex

        if isActive {
            contentBackground.setFill()
            rect.fill()
        } else if hoveredTab == index {
            hoverBackground.setFill()
            rect.fill()
        }

        // Separator between adjacent inactive tabs. Skipped next to the active tab
        // because the active tab's own fill already provides the edge.
        if !isActive && index != activeIndex + 1 && index > 0 {
            contentForeground.withAlphaComponent(0.10).setFill()
            NSRect(x: rect.minX, y: 6, width: 1, height: rect.height - 12).fill()
        }

        let textAlpha: CGFloat = isActive ? 0.95 : 0.55
        var textLeft = rect.minX + Self.horizontalPadding

        if let symbol = NSImage(systemSymbolName: item(index).symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular)) {
            symbol.isTemplate = true
            let side: CGFloat = 12
            let symbolRect = NSRect(
                x: textLeft, y: (rect.height - side) / 2, width: side, height: side)
            // Template images render black when drawn directly; tint by filling
            // source-atop over the just-drawn glyph.
            NSGraphicsContext.saveGraphicsState()
            symbol.draw(in: symbolRect)
            contentForeground.withAlphaComponent(textAlpha).set()
            symbolRect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            textLeft = symbolRect.maxX + 5
        }

        // Reserve the close box so a long title never draws underneath the ×.
        let textRight = closeRect(rect).minX - 4
        if textRight > textLeft {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attributed = NSAttributedString(
                string: item(index).title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: isActive ? .medium : .regular),
                    .foregroundColor: contentForeground.withAlphaComponent(textAlpha),
                    .paragraphStyle: paragraph,
                ]
            )
            let textHeight = attributed.size().height
            attributed.draw(
                in: NSRect(
                    x: textLeft, y: (rect.height - textHeight) / 2,
                    width: textRight - textLeft, height: textHeight))
        }

        // The × is drawn only for the active tab or the hovered one. Showing it on
        // every tab turns a quiet rail into a row of buttons.
        //
        // An edited tab shows a dot in that same box until you hover it, at which
        // point the × takes over — Safari's and VS Code's arrangement. Sharing the
        // box rather than adding a second affordance is deliberate: the dot has to
        // be visible on *inactive* tabs (that is the whole point of an unsaved
        // marker) and the close box is the only slot already reserved on those.
        if item(index).isEdited && hoveredTab != index {
            drawEditedDot(in: closeRect(rect))
        } else if isActive || hoveredTab == index {
            drawCloseGlyph(in: closeRect(rect), emphasised: hoveredClose == index)
        }
    }

    private func drawEditedDot(in box: NSRect) {
        let side: CGFloat = 7
        let dot = NSRect(
            x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        contentForeground.withAlphaComponent(0.75).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private func drawCloseGlyph(in box: NSRect, emphasised: Bool) {
        if emphasised {
            contentForeground.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        }
        let inset = box.insetBy(dx: 4.5, dy: 4.5)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: inset.minX, y: inset.minY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        path.move(to: NSPoint(x: inset.minX, y: inset.maxY))
        path.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        contentForeground.withAlphaComponent(emphasised ? 0.95 : 0.6).setStroke()
        path.stroke()
    }

    private func drawNewButton(_ layout: Layout) {
        let rect = newButtonRect(layout)
        if isHoveringNewButton {
            hoverBackground.setFill()
            rect.fill()
        }
        let arm: CGFloat = 4.5
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre.x - arm, y: centre.y))
        path.line(to: NSPoint(x: centre.x + arm, y: centre.y))
        path.move(to: NSPoint(x: centre.x, y: centre.y - arm))
        path.line(to: NSPoint(x: centre.x, y: centre.y + arm))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        contentForeground.withAlphaComponent(isHoveringNewButton ? 0.95 : 0.55).setStroke()
        path.stroke()
    }

    /// A downward chevron, matching the disclosure shape AppKit uses for
    /// "there is more here than fits" (NSPopUpButton's pull-down arrow). Drawn as a
    /// path rather than an SF Symbol for the same reason the × is: the symbol would
    /// need the tint-by-sourceAtop dance in `drawTab` for two strokes.
    private func drawOverflowButton(in rect: NSRect) {
        if isHoveringOverflowButton {
            hoverBackground.setFill()
            rect.fill()
        }
        let halfWidth: CGFloat = 4
        let halfHeight: CGFloat = 2.5
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre.x - halfWidth, y: centre.y + halfHeight))
        path.line(to: NSPoint(x: centre.x, y: centre.y - halfHeight))
        path.line(to: NSPoint(x: centre.x + halfWidth, y: centre.y + halfHeight))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        contentForeground.withAlphaComponent(isHoveringOverflowButton ? 0.95 : 0.55).setStroke()
        path.stroke()
    }

    /// Every document, hidden ones included, as a menu. This is the affordance that
    /// makes the overflow strategy safe: whatever the window is showing, one click
    /// reaches any document. Built fresh on each click because `items` is replaced
    /// wholesale by `reload` and a cached menu would go stale silently.
    private func showOverflowMenu(from rect: NSRect) {
        let menu = NSMenu()
        for index in items.indices {
            let entry = NSMenuItem(
                title: item(index).title, action: #selector(overflowMenuDidPick(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.tag = index
            // `.on` rather than a custom glyph so VoiceOver and the menu's own
            // drawing both report the selection without extra work.
            entry.state = index == activeIndex ? .on : .off
            entry.image = NSImage(
                systemSymbolName: item(index).symbolName, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        // Anchored under the chevron so the menu visually belongs to the button that
        // opened it; `nil` event means AppKit synthesises the tracking for us.
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY), in: self)
    }

    @objc private func overflowMenuDidPick(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        delegate?.tabStrip(self, didSelect: sender.tag)
    }

    private func item(_ index: Int) -> Item { items[index] }

    // MARK: - Accessibility
    //
    // This is the bill for hand-rolling the document tab level (see the file header:
    // native window tabs were spent on Spaces, so they were not available here).
    // Native NSTabView / NSWindow tabs ship their accessibility tree for free; a
    // single NSView with `draw(_:)` and rect hit-testing ships *nothing* — before
    // this, VoiceOver saw one unlabelled group with no tabs, no titles, no selection
    // and no close buttons, and there was no way to reach a document without a mouse
    // or the ⌘1–9 chords in `KeyBindings.swift`.
    //
    // Modelled as a tab group whose children are radio-button-role tabs, which is the
    // shape AppKit's own NSTabView reports and therefore the one VoiceOver already
    // knows how to narrate ("tab 2 of 5, selected"). The children are proxy elements
    // (`NSAccessibilityElement`) rather than real subviews on purpose: adding per-tab
    // subviews is exactly the teardown churn the file header rejects, since the shell
    // rewrites titles constantly via OSC 0/2.
    //
    // Only the *visible* window of tabs gets a child element, matching what the
    // overflow layout actually presents; the documents the window is not showing are
    // reachable through the overflow chevron's own menu, which AppKit makes
    // accessible for free (NSMenu is a real menu, and the picked item carries
    // `.on` state).

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }

    override func accessibilityLabel() -> String? { "Document tabs" }

    /// The active document's title, so a VoiceOver user who lands on the group hears
    /// what is selected without having to walk into the children.
    override func accessibilityValue() -> Any? {
        guard items.indices.contains(activeIndex) else { return nil }
        return item(activeIndex).title
    }

    override func accessibilityChildren() -> [Any]? {
        let layout = self.layout
        var children: [Any] = layout.visible.compactMap { tabElement($0, layout) }
        if let overflow = overflowButtonRect(layout) {
            children.append(
                buttonElement(
                    rect: overflow, label: "All documents",
                    help: "Shows every open document, including tabs that do not fit.",
                    action: #selector(accessibilityShowOverflowMenu)))
        }
        children.append(
            buttonElement(
                rect: newButtonRect(layout), label: "New document",
                help: "Opens a new terminal in this Space.",
                action: #selector(accessibilityRequestNewDocument)))
        return children
    }

    /// Rebuilt on demand rather than cached: `reload` swaps `items` wholesale and the
    /// layout window follows `activeIndex`, so a cached tree would go stale on every
    /// selection change and every title repaint. Cheap — the strip holds a handful of
    /// tabs, and AppKit only asks while an assistive client is actually attached.
    private func tabElement(_ index: Int, _ layout: Layout) -> NSAccessibilityElement? {
        guard let rect = tabRect(index, layout) else { return nil }
        let element = TabProxy()
        element.strip = self
        element.index = index
        element.setAccessibilityRole(.radioButton)
        // `.radioButton` inside a `.tabGroup` is the NSTabView shape: subrole
        // `.tabButtonSubrole` is what makes VoiceOver say "tab" and announce the
        // "n of m" position instead of reading it as a lone radio button.
        element.setAccessibilitySubrole(.tabButtonSubrole)
        element.setAccessibilityLabel(item(index).title)
        // Value carries selection because that is where AXRadioButton publishes it;
        // `setAccessibilitySelected` alone is not narrated on this role.
        element.setAccessibilityValue(index == activeIndex ? 1 : 0)
        element.setAccessibilitySelected(index == activeIndex)
        if item(index).isEdited {
            // The unsaved dot in `drawTab` is purely visual, so it is invisible to
            // VoiceOver unless it is said out loud somewhere.
            element.setAccessibilityHelp("Has unsaved changes.")
        }
        element.setAccessibilityParent(self)
        element.setAccessibilityFrameInParentSpace(rect)
        return element
    }

    private func buttonElement(
        rect: NSRect, label: String, help: String, action: Selector
    ) -> NSAccessibilityElement {
        let element = ActionProxy()
        element.strip = self
        element.pressAction = action
        element.setAccessibilityRole(.button)
        element.setAccessibilityLabel(label)
        element.setAccessibilityHelp(help)
        element.setAccessibilityParent(self)
        element.setAccessibilityFrameInParentSpace(rect)
        return element
    }

    // Targets for the proxy elements' actions. They live on the strip rather than on
    // the proxies so the proxies stay dumb rects and there is one place that talks to
    // the delegate — the same reasoning as `mouseDown` being the only mouse path.

    fileprivate func accessibilitySelectTab(_ index: Int) {
        guard items.indices.contains(index) else { return }
        delegate?.tabStrip(self, didSelect: index)
    }

    fileprivate func accessibilityCloseTab(_ index: Int) {
        guard items.indices.contains(index) else { return }
        delegate?.tabStrip(self, didRequestClose: index)
    }

    @objc fileprivate func accessibilityRequestNewDocument() {
        delegate?.tabStripDidRequestNewDocument(self)
    }

    @objc fileprivate func accessibilityShowOverflowMenu() {
        guard let rect = overflowButtonRect(layout) else { return }
        showOverflowMenu(from: rect)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layout = self.layout
        let tab = tabIndex(at: point, layout)
        let close = tab.flatMap { index -> Int? in
            guard let rect = tabRect(index, layout) else { return nil }
            return closeRect(rect).contains(point) ? index : nil
        }
        let newButton = newButtonRect(layout).contains(point)
        let overflow = overflowButtonRect(layout)?.contains(point) ?? false
        // Only repaint on an actual state change: mouseMoved fires continuously,
        // and the terminal underneath deserves the frames more than this rail does.
        guard tab != hoveredTab || close != hoveredClose || newButton != isHoveringNewButton
            || overflow != isHoveringOverflowButton
        else { return }
        hoveredTab = tab
        hoveredClose = close
        isHoveringNewButton = newButton
        isHoveringOverflowButton = overflow
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTab = nil
        hoveredClose = nil
        isHoveringNewButton = false
        isHoveringOverflowButton = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let layout = self.layout
        if newButtonRect(layout).contains(point) {
            delegate?.tabStripDidRequestNewDocument(self)
            return
        }
        // Tested before tabs: the chevron is pinned to the right edge and the last
        // visible tab ends exactly where it starts, so a hit here is unambiguous.
        if let overflow = overflowButtonRect(layout), overflow.contains(point) {
            showOverflowMenu(from: overflow)
            return
        }
        guard let index = tabIndex(at: point, layout), let rect = tabRect(index, layout) else {
            return
        }
        // Close wins over select: the × sits inside the tab's own rect, so testing
        // it second would select the tab and never close it.
        if (index == activeIndex || hoveredTab == index), closeRect(rect).contains(point) {
            delegate?.tabStrip(self, didRequestClose: index)
        } else {
            delegate?.tabStrip(self, didSelect: index)
        }
    }
}

/// One tab, as far as an assistive client is concerned. Holds only an index and a
/// weak strip reference; every question about geometry or state is answered by the
/// strip, so there is no second copy of the layout to disagree with `draw`.
@MainActor
private final class TabProxy: NSAccessibilityElement {
    weak var strip: DocumentTabStrip?
    var index: Int = 0

    /// `accessibilityPerformPress` is what VoiceOver's ⌃⌥space and Full Keyboard
    /// Access both route to, so select has to be press — not a custom action.
    ///
    /// `NSAccessibilityElement`'s action methods are not `@MainActor` in the SDK, so
    /// under Swift 6 the override is nonisolated and cannot touch this type's stored
    /// properties directly. `assumeIsolated` rather than a hop: AppKit dispatches
    /// accessibility actions on the main thread, and hopping would make the return
    /// value a lie — the client reads `Bool` synchronously to decide whether to
    /// announce the action as performed.
    override nonisolated func accessibilityPerformPress() -> Bool {
        // `nonisolated(unsafe) let` on the self copy is what lets a non-Sendable
        // element cross into the closure: without it Swift 6 region isolation reports
        // "sending 'self' risks causing data races". Safe here for the reason above —
        // the only caller is AppKit's accessibility dispatch, which is main-thread.
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated {
            guard let strip = element.strip else { return false }
            strip.accessibilitySelectTab(element.index)
            return true
        }
    }

    /// Close is exposed as the standard "delete" action rather than a bespoke one:
    /// VoiceOver offers it in the actions menu (⌃⌥⌘space) with wording the user has
    /// already learned elsewhere, and Safari's tabs use the same mapping.
    override nonisolated func accessibilityPerformDelete() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated {
            guard let strip = element.strip else { return false }
            strip.accessibilityCloseTab(element.index)
            return true
        }
    }
}

/// The "+" and the overflow chevron. Same proxy trick as `TabProxy`, but the press
/// target is a selector on the strip because these two do not carry an index.
@MainActor
private final class ActionProxy: NSAccessibilityElement {
    weak var strip: DocumentTabStrip?
    var pressAction: Selector?

    /// Nonisolated + `assumeIsolated` for the same reason as `TabProxy`'s overrides.
    override nonisolated func accessibilityPerformPress() -> Bool {
        nonisolated(unsafe) let element = self
        return MainActor.assumeIsolated {
            guard let strip = element.strip, let action = element.pressAction else {
                return false
            }
            // `perform(_:)` rather than a stored closure: a closure capturing the
            // strip would need `@Sendable` reasoning, and AFK.md's conventions rule
            // out adding `Sendable` annotations to this codebase.
            strip.perform(action)
            return true
        }
    }
}

private extension NSRect {
    /// The parts of `self` left over once `excluded` is removed horizontally.
    /// Used to draw the strip's baseline everywhere except under the active tab.
    func slices(excluding excluded: NSRect) -> [NSRect] {
        guard !excluded.isEmpty, excluded.maxX > minX, excluded.minX < maxX else { return [self] }
        var result: [NSRect] = []
        if excluded.minX > minX {
            result.append(NSRect(x: minX, y: minY, width: excluded.minX - minX, height: height))
        }
        if excluded.maxX < maxX {
            result.append(NSRect(x: excluded.maxX, y: minY, width: maxX - excluded.maxX, height: height))
        }
        return result
    }
}
