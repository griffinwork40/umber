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
    /// A tab was dragged to a new slot. The owner must apply the same move to its
    /// own document array — the strip's `items` are a projection of that array, so
    /// the next `reload` overwrites whatever the strip did locally.
    func tabStrip(_ strip: DocumentTabStrip, didMove index: Int, to destination: Int)
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

    /// The floor tabs compress to before the strip starts scrolling. 84pt keeps the
    /// kind symbol *and* ~5 characters of title, which is the point at which a tab
    /// is still identifiable; below that a strip of 14 tabs is 14 identical slivers
    /// and the overflow menu is the better answer anyway.
    private static let compressedTabWidth: CGFloat = 84
    private static let maxTabWidth: CGFloat = 210
    private static let newButtonWidth: CGFloat = 30
    private static let overflowButtonWidth: CGFloat = 24
    private static let closeBoxSide: CGFloat = 15
    private static let horizontalPadding: CGFloat = 8

    weak var delegate: DocumentTabStripDelegate?

    private var items: [Item] = []
    private var activeIndex: Int = 0
    private var hoveredTab: Int?
    private var hoveredClose: Int?
    private var isHoveringNewButton = false
    private var isHoveringOverflow = false

    /// An in-progress reorder. Nil the overwhelming majority of the time.
    private struct Drag {
        /// Where the tab started, so `mouseUp` can tell the owner what moved where.
        let origin: Int
        /// Where it currently sits. The strip reorders its own `items` live, so this
        /// is also the tab's present index.
        var current: Int
        /// Pointer x minus the tab's minX at mouse-down, so the tab does not jump to
        /// centre itself under the cursor the instant the drag begins.
        let grabOffset: CGFloat
        /// Cleared until the pointer passes the threshold — a click is a drag of zero
        /// distance, and treating it as a reorder would fight the select gesture.
        var isActive = false
    }

    private var drag: Drag?

    /// Index of the leftmost drawn tab once the strip is scrolling. Zero whenever
    /// every tab fits, which is the overwhelmingly common case.
    private var scrollOffset = 0
    /// Wheel/trackpad travel not yet spent on a whole-tab step. Whole steps only:
    /// a half-drawn tab at the left edge reads as a rendering bug, not as scroll.
    private var scrollAccumulator: CGFloat = 0

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
        clampScrollOffset()
        scrollToActive()
        rebuildAccessibilityChildren()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Widening the window can make the whole strip fit again, at which point a
        // stale non-zero offset would leave a permanent gap where tab 0 belongs.
        clampScrollOffset()
        // Every element's frame is derived from `tabRect`, so a resize invalidates
        // all of them — VoiceOver's cursor would otherwise draw over stale geometry.
        rebuildAccessibilityChildren()
        needsDisplay = true
    }

    // MARK: - Geometry
    //
    // One source of truth for the layout, consumed by both drawing and hit
    // testing. Two independent copies of this arithmetic is how a strip ends up
    // closing the tab next to the one you clicked.
    //
    // Overflow, in two stages — compress, then scroll (plan §12.2's cost of
    // hand-rolling this level).
    //
    // What was here before divided the available width evenly and clamped it at a
    // 96pt floor, which meant that past ~8 documents on a 900pt window the later
    // tabs were laid out past the right edge with no scroll, no chevron and no
    // compression: unreachable by mouse, reachable only via ⌘1–9 (which stops at 9)
    // and ⌘⌥←/→. Tabs that exist but cannot be clicked are a worse failure than
    // small tabs.
    //
    // Compression alone was rejected: with 20 documents an even split is 42pt, which
    // is narrower than the close box plus its padding, so every tab becomes an
    // unlabelled square and the strip stops being a strip. Scrolling alone was
    // rejected too — it would start hiding tabs at 5 documents on a narrow window
    // while there was still plenty of room to make them thinner. So: compress down
    // to `compressedTabWidth`, and only once that no longer fits does the strip
    // scroll, with an overflow chevron that lists every document by name so the
    // hidden ones stay reachable in one gesture rather than N wheel ticks.

    /// Width available to tabs. The new-document button is always reserved; the
    /// overflow chevron only when it is actually shown.
    private var tabTrackWidth: CGFloat {
        max(bounds.width - Self.newButtonWidth - (isOverflowing ? Self.overflowButtonWidth : 0), 0)
    }

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        // Computed against the *un*-reduced track on purpose: deciding the width
        // from `tabTrackWidth` would make the width depend on `isOverflowing`,
        // which depends on the width. This ordering keeps it a straight line.
        let available = max(bounds.width - Self.newButtonWidth, 0)
        let even = available / CGFloat(items.count)
        return min(max(even, Self.compressedTabWidth), Self.maxTabWidth)
    }

    /// True when even fully-compressed tabs cannot all be shown.
    private var isOverflowing: Bool {
        guard !items.isEmpty else { return false }
        let needed = CGFloat(items.count) * tabWidth
        return needed > max(bounds.width - Self.newButtonWidth, 0) + 0.5
    }

    /// How many tabs fit in the track at the current width. At least one, so the
    /// arithmetic below never divides a window down to zero visible tabs.
    private var visibleCount: Int {
        guard tabWidth > 0 else { return 0 }
        return max(Int(tabTrackWidth / tabWidth), 1)
    }

    private var maxScrollOffset: Int { max(items.count - visibleCount, 0) }

    private func clampScrollOffset() {
        scrollOffset = min(max(scrollOffset, 0), maxScrollOffset)
    }

    /// Keep the selected tab on screen. ⌘1–9 and ⌘⌥←/→ can select a tab that is
    /// currently scrolled out; without this the selection would appear to do nothing.
    private func scrollToActive() {
        guard isOverflowing, items.indices.contains(activeIndex) else { return }
        if activeIndex < scrollOffset {
            scrollOffset = activeIndex
        } else if activeIndex >= scrollOffset + visibleCount {
            scrollOffset = activeIndex - visibleCount + 1
        }
        clampScrollOffset()
    }

    /// Indices currently drawn. One extra past the fitting count is deliberate: a
    /// partially-clipped trailing tab is the standard "there is more this way" cue,
    /// and it is drawn clipped rather than omitted so the strip never looks like it
    /// ends exactly at the chevron.
    private var visibleRange: Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        guard isOverflowing else { return items.indices.lowerBound..<items.count }
        let end = min(scrollOffset + visibleCount + 1, items.count)
        return scrollOffset..<end
    }

    private func tabRect(_ index: Int) -> NSRect {
        NSRect(
            x: CGFloat(index - scrollOffset) * tabWidth, y: 0,
            width: tabWidth, height: bounds.height)
    }

    /// Where a tab is actually painted. Identical to its slot except for the one tab
    /// being dragged, which follows the pointer while its slot stays empty-looking
    /// underneath — the neighbours have already shuffled into their new order, so the
    /// strip previews the result rather than announcing it only on release.
    private func drawnTabRect(_ index: Int) -> NSRect {
        guard let drag, drag.isActive, drag.current == index else { return tabRect(index) }
        var rect = tabRect(index)
        // Clamped to the track: a tab that can be flung off the left edge or under the
        // chevron looks broken, and the drop target is clamped identically anyway.
        rect.origin.x = min(max(dragFloatingMinX, 0), max(tabTrackWidth - tabWidth, 0))
        return rect
    }

    /// The pointer's x minus where it grabbed the tab, so the tab keeps the grip point
    /// it was picked up by.
    private var dragFloatingMinX: CGFloat = 0

    private func closeRect(_ index: Int) -> NSRect { closeRect(in: drawnTabRect(index)) }

    /// Derived from a rect rather than an index so a dragged tab's × travels with it.
    private func closeRect(in tab: NSRect) -> NSRect {
        NSRect(
            x: tab.maxX - Self.horizontalPadding - Self.closeBoxSide,
            y: (tab.height - Self.closeBoxSide) / 2,
            width: Self.closeBoxSide,
            height: Self.closeBoxSide
        )
    }

    /// The chevron, when overflowing. Pinned to the right of the track and left of
    /// the new-document button so both trailing controls keep a fixed home — a
    /// chevron that slides as tabs open is a chevron nobody learns the position of.
    private var overflowButtonRect: NSRect {
        guard isOverflowing else { return .zero }
        return NSRect(
            x: bounds.width - Self.newButtonWidth - Self.overflowButtonWidth, y: 0,
            width: Self.overflowButtonWidth, height: bounds.height)
    }

    private var newButtonRect: NSRect {
        // Pinned right while overflowing (there is no slack to sit after the tabs),
        // and packed directly after the last tab otherwise — which is where it has
        // always been and is what makes a two-tab strip look deliberate.
        let x = isOverflowing
            ? bounds.width - Self.newButtonWidth
            : CGFloat(items.count) * tabWidth
        return NSRect(x: x, y: 0, width: Self.newButtonWidth, height: bounds.height)
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        guard tabWidth > 0 else { return nil }
        // Both trailing controls sit over the tab track's arithmetic once the strip
        // is scrolling, so they must win the hit test or the last tab swallows them.
        if overflowButtonRect.contains(point) || newButtonRect.contains(point) { return nil }
        let index = Int(point.x / tabWidth) + scrollOffset
        guard items.indices.contains(index) else { return nil }
        // A trailing tab drawn clipped under the chevron is not clickable in the
        // part that is hidden — the visible sliver is, and that is enough.
        return index
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

        // Clip the tabs to the track so a scrolled strip's trailing tab is cut off
        // at the chevron instead of painting over it.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: tabTrackWidth, height: bounds.height))
            .setClip()
        // The dragged tab is drawn last so it floats over its neighbours instead of
        // being half-covered by whichever one happens to come after it.
        let floating = (drag?.isActive == true) ? drag?.current : nil
        for index in visibleRange where index != floating {
            drawTab(index)
        }
        if let floating, visibleRange.contains(floating) { drawTab(floating) }
        NSGraphicsContext.restoreGraphicsState()

        if isOverflowing { drawOverflowChevron() }
        drawNewButton()

        // Hairline under the *inactive* stretch only. Running it under the active
        // tab too would draw a line between the tab and its own content, which is
        // precisely the seam this design removes.
        contentForeground.withAlphaComponent(0.12).setFill()
        let hairline = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        // Exclude the active tab only while it is actually on screen — scrolled out
        // of view its rect is off to one side, and subtracting it would punch a gap
        // in the baseline under a tab that is not there.
        let activeIsVisible = visibleRange.contains(activeIndex)
        for slice in hairline.slices(excluding: activeIsVisible ? tabRect(activeIndex) : .zero) {
            slice.fill()
        }
    }

    /// Two stacked chevrons (a "more" affordance), not a count badge: the point is
    /// that clicking here lists the documents, and `⌄⌄` reads as a menu everywhere
    /// on this platform.
    private func drawOverflowChevron() {
        let rect = overflowButtonRect
        if isHoveringOverflow {
            hoverBackground.setFill()
            rect.fill()
        }
        let path = NSBezierPath()
        let halfWidth: CGFloat = 3.5
        let depth: CGFloat = 2.5
        for offsetY in [CGFloat(2.5), CGFloat(-2.5)] {
            let apexY = rect.midY + offsetY
            path.move(to: NSPoint(x: rect.midX - halfWidth, y: apexY + depth))
            path.line(to: NSPoint(x: rect.midX, y: apexY - depth))
            path.line(to: NSPoint(x: rect.midX + halfWidth, y: apexY + depth))
        }
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        contentForeground.withAlphaComponent(isHoveringOverflow ? 0.95 : 0.55).setStroke()
        path.stroke()
    }

    private func drawTab(_ index: Int) {
        let rect = drawnTabRect(index)
        let isActive = index == activeIndex
        let isDragging = drag?.isActive == true && drag?.current == index

        if isActive || isDragging {
            // A dragged inactive tab gets the active fill too: it has been lifted out
            // of the rail, and a floating tab in rail colours reads as a hole rather
            // than as a thing being carried.
            contentBackground.setFill()
            rect.fill()
        } else if hoveredTab == index {
            hoverBackground.setFill()
            rect.fill()
        }

        if isDragging {
            // A border, not a shadow: the strip is 30pt of flat colour and a drop
            // shadow at this scale reads as blur. The outline is what says "detached".
            contentForeground.withAlphaComponent(0.28).setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }

        // Separator between adjacent inactive tabs. Skipped next to the active tab
        // because the active tab's own fill already provides the edge, and on the
        // leftmost *drawn* tab (not just tab 0) because at x = 0 it is a hairline
        // along the window edge rather than a divider between two things.
        if !isActive && !isDragging && index != activeIndex + 1 && index > visibleRange.lowerBound {
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
        let textRight = closeRect(index).minX - 4
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
            drawEditedDot(in: closeRect(index))
        } else if isActive || hoveredTab == index {
            drawCloseGlyph(in: closeRect(index), emphasised: hoveredClose == index)
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

    private func drawNewButton() {
        let rect = newButtonRect
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

    private func item(_ index: Int) -> Item { items[index] }

    // MARK: - Accessibility
    //
    // This is the bill for hand-rolling this tab level, and it comes due here
    // (plan §12.2). The Spaces level gets accessibility free because those are real
    // `NSWindow` tabs; documents are one `NSView` of hand-drawn rects, so before
    // this there was literally nothing here — VoiceOver saw a single unlabelled
    // group and the *only* `accessibility` mentions in the whole app were
    // `NSImage(systemSymbolName:accessibilityDescription: nil)`. A user on VoiceOver
    // could not discover that a second document existed, let alone switch to one.
    //
    // `NSAccessibilityElement` children rather than real subviews, which is exactly
    // the case Apple documents them for: "if a single NSView subclass draws 4
    // buttons, it would vend 4 NSAccessibilityElements as accessibilityChildren"
    // (`NSAccessibilityElement.h`). Real subviews would reintroduce the per-tab
    // teardown churn this strip was drawn by hand to avoid (see the file header) —
    // the shell repaints titles constantly via OSC 0/2. The elements are cheap
    // value-carrying shells rebuilt on `reload`, so a title change costs three small
    // objects, not three views entering and leaving a hierarchy.
    //
    // Also vended: the two chrome buttons, so "new document" and the overflow list
    // are reachable rather than being invisible hot rectangles.

    private var accessibilityElements: [NSAccessibilityElement] = []

    /// Held so tab elements can call back without retaining the strip. `weak var
    /// strip` inside each element would work equally well; one shared box means one
    /// reference to nil out and no per-element weak slot.
    private lazy var accessibilityBridge = TabStripAccessibilityBridge(strip: self)

    override func accessibilityRole() -> NSAccessibility.Role? {
        // `.tabGroup`, matching what an `NSTabView` reports — these behave as tabs
        // even though they are not built from one, and VoiceOver's tab-specific
        // announcements ("tab 3 of 7, selected") depend on this role.
        .tabGroup
    }

    override func accessibilityLabel() -> String? { "Documents" }

    override func accessibilityChildren() -> [Any]? { accessibilityElements }

    /// Without this, VoiceOver's "interact with the tab group" gesture has no notion
    /// of which tab is current and starts from the left every time.
    override func accessibilitySelectedChildren() -> [Any]? {
        guard items.indices.contains(activeIndex),
              let element = accessibilityElements.first(where: {
                  ($0 as? TabAccessibilityElement)?.index == activeIndex
              })
        else { return nil }
        return [element]
    }

    private func rebuildAccessibilityChildren() {
        var elements: [NSAccessibilityElement] = []
        // Only the visible range: an element whose frame is off-screen is one
        // VoiceOver will happily route the cursor to and then draw its highlight
        // somewhere the user cannot see. The overflow menu — a real NSMenu — is the
        // accessible path to a scrolled-out tab, which is one of the reasons the
        // menu lists every document rather than only the hidden ones.
        for index in visibleRange {
            let element = TabAccessibilityElement(
                bridge: accessibilityBridge, index: index, item: item(index),
                position: index + 1, total: items.count,
                isSelected: index == activeIndex)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(tabRect(index))
            elements.append(element)
        }
        if isOverflowing {
            elements.append(
                ChromeAccessibilityElement(
                    bridge: accessibilityBridge, parent: self, frame: overflowButtonRect,
                    kind: .overflow, label: "All Documents",
                    // Says what the button *does*, since a chevron has no text to read.
                    help: "Show a list of all \(items.count) open documents"))
        }
        elements.append(
            ChromeAccessibilityElement(
                bridge: accessibilityBridge, parent: self, frame: newButtonRect,
                kind: .newDocument, label: "New Terminal",
                help: "Open a new terminal document (Command-T)"))
        accessibilityElements = elements
    }

    /// Called by the tab elements. Kept here rather than exposing `delegate` so the
    /// accessibility path goes through the same two calls the mouse path does.
    fileprivate func accessibilitySelect(index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        delegate?.tabStrip(self, didSelect: index)
        return true
    }

    fileprivate func accessibilityClose(index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        delegate?.tabStrip(self, didRequestClose: index)
        return true
    }

    fileprivate func accessibilityPerformChrome(_ kind: ChromeAccessibilityElement.Kind) -> Bool {
        switch kind {
        case .newDocument:
            delegate?.tabStripDidRequestNewDocument(self)
            return true
        case .overflow:
            // Opening a real NSMenu is what makes a scrolled-out tab reachable
            // without a pointer — NSMenu carries its own accessibility.
            presentOverflowMenu()
            return true
        }
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
        let tab = tabIndex(at: point)
        let close = tab.flatMap { closeRect($0).contains(point) ? $0 : nil }
        let newButton = newButtonRect.contains(point)
        let overflow = overflowButtonRect.contains(point)
        // Only repaint on an actual state change: mouseMoved fires continuously,
        // and the terminal underneath deserves the frames more than this rail does.
        guard tab != hoveredTab || close != hoveredClose || newButton != isHoveringNewButton
            || overflow != isHoveringOverflow
        else { return }
        hoveredTab = tab
        hoveredClose = close
        isHoveringNewButton = newButton
        isHoveringOverflow = overflow
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTab = nil
        hoveredClose = nil
        isHoveringNewButton = false
        isHoveringOverflow = false
        needsDisplay = true
    }

    /// Horizontal wheel/trackpad scroll pans the strip, matching Safari's tab bar.
    /// Vertical is honoured too — a plain mouse wheel has no horizontal axis, and
    /// ignoring it would make the strip unpannable on that hardware.
    override func scrollWheel(with event: NSEvent) {
        guard isOverflowing else {
            // Let it through: with everything visible the strip has nothing to pan,
            // and swallowing the event would eat a scroll aimed past this rail.
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        scrollAccumulator += delta
        // One tab per this much travel. Tuned against a trackpad rather than derived:
        // a whole-tab step per pixel makes the strip unusable, and per-tabWidth makes
        // it feel stuck.
        let travelPerTab: CGFloat = 24
        let steps = Int(scrollAccumulator / travelPerTab)
        guard steps != 0 else { return }
        scrollAccumulator -= CGFloat(steps) * travelPerTab
        // Natural direction: content follows the fingers, so scrolling right (positive
        // deltaX) reveals earlier tabs.
        let before = scrollOffset
        scrollOffset -= steps
        clampScrollOffset()
        guard scrollOffset != before else { return }
        // Hover is stale the moment the tabs move under a stationary pointer.
        hoveredTab = nil
        hoveredClose = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if newButtonRect.contains(point) {
            delegate?.tabStripDidRequestNewDocument(self)
            return
        }
        if isOverflowing, overflowButtonRect.contains(point) {
            presentOverflowMenu()
            return
        }
        guard let index = tabIndex(at: point) else { return }
        // Close wins over select: the × sits inside the tab's own rect, so testing
        // it second would select the tab and never close it.
        if (index == activeIndex || hoveredTab == index), closeRect(index).contains(point) {
            delegate?.tabStrip(self, didRequestClose: index)
            return
        }
        // Select on mouse-DOWN, before the drag begins, matching Safari and Chrome:
        // you drag the tab you are looking at, and deferring selection to mouse-up
        // would show you the wrong document for the whole duration of the drag.
        delegate?.tabStrip(self, didSelect: index)
        drag = Drag(origin: index, current: index, grabOffset: point.x - tabRect(index).minX)
    }

    /// Middle-click closes, which is what every browser and Ghostty do and therefore
    /// what a user tries without being told. `otherMouseDown` rather than a button
    /// check in `mouseDown`: AppKit routes buttons past the second to the "other"
    /// family entirely, so it would never arrive there.
    override func otherMouseDown(with event: NSEvent) {
        // Guard the button number — `otherMouseDown` also fires for buttons 3, 4, 5
        // (thumb buttons), and closing a document on a stray thumb press would be a
        // data-loss gesture nobody asked for.
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tabIndex(at: point) else {
            super.otherMouseDown(with: event)
            return
        }
        // Goes through the same delegate call the × does, so `documentShouldClose()`
        // still gets to veto — a middle-click must not be a way around the unsaved
        // prompt (`SpaceViewController.closeDocument(at:)`).
        delegate?.tabStrip(self, didRequestClose: index)
    }

    // MARK: - Drag to reorder
    //
    // Hand-rolled from mouseDragged rather than NSDraggingSource. There are no drag
    // APIs anywhere else in `app/Sources`, and the dragging-session machinery buys
    // things this gesture does not want: a pasteboard type, a drag image, and
    // cross-window/cross-app drops. Documents are not transferable objects — a tab is
    // a live `SpaceDocument` holding a pty or an editable buffer, so "drop it in
    // another window" is not a reorder but a document *migration*, which would need
    // the view to move between Spaces and is well outside this strip. Reordering
    // within the strip is a slot-index swap, and mouseDragged gives it directly.
    //
    // Moving to NSDraggingSource is the right call the day drag-out-to-another-Space
    // is on the table — the Spaces level already gets that free from real NSWindow
    // tabs (plan §12.3), so it may never be.

    /// Pointer travel before a press becomes a drag. 4pt is roughly AppKit's own
    /// threshold for the same distinction and comfortably above hand tremor.
    private static let dragThreshold: CGFloat = 4

    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let point = convert(event.locationInWindow, from: nil)

        if !drag.isActive {
            guard abs(point.x - (tabRect(drag.current).minX + drag.grabOffset))
                >= Self.dragThreshold
            else { return }
            drag.isActive = true
        }

        dragFloatingMinX = point.x - drag.grabOffset
        // Which slot the tab's *centre* is over. Centre rather than leading edge so
        // the swap happens when the tab has visibly passed its neighbour, instead of
        // flickering the moment its left edge crosses a boundary.
        let centre = min(max(dragFloatingMinX, 0), max(tabTrackWidth - tabWidth, 0)) + tabWidth / 2
        let target = min(max(Int(centre / tabWidth) + scrollOffset, 0), items.count - 1)

        if target != drag.current {
            // Reorder the strip's own copy immediately so neighbours slide out of the
            // way live. The owner is told once, on mouse-up: telling it per-step would
            // fire a document reorder (and a `reload`) on every pixel of travel.
            let moved = items.remove(at: drag.current)
            items.insert(moved, at: target)
            // The selection is an index into the same array, so it has to travel too
            // or a reorder silently changes which document is showing.
            activeIndex = Self.indexAfterMove(
                activeIndex, from: drag.current, to: target)
            drag.current = target
            rebuildAccessibilityChildren()
        }
        self.drag = drag
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            dragFloatingMinX = 0
        }
        guard let drag, drag.isActive, drag.current != drag.origin else {
            // A press that never became a drag already did its work in mouseDown.
            needsDisplay = true
            return
        }
        delegate?.tabStrip(self, didMove: drag.origin, to: drag.current)
        needsDisplay = true
    }

    /// Where `index` ends up after the element at `from` is moved to `to`.
    ///
    /// Pulled out and made static because it is the one piece of this gesture that is
    /// pure arithmetic and easy to get subtly wrong — the moved element's own index
    /// becomes `to`, and everything strictly between the two shifts by one *towards*
    /// the origin.
    static func indexAfterMove(_ index: Int, from: Int, to: Int) -> Int {
        if index == from { return to }
        if from < to && index > from && index <= to { return index - 1 }
        if from > to && index >= to && index < from { return index + 1 }
        return index
    }

    // MARK: - Overflow menu

    /// Lists every document, not just the hidden ones. A menu whose contents change
    /// with the scroll position is a menu you have to read every time; a stable full
    /// list with a checkmark on the active one can be used from muscle memory.
    private func presentOverflowMenu() {
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let entry = NSMenuItem(
                title: item.title, action: #selector(overflowMenuDidPick(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = index == activeIndex ? .on : .off
            entry.image = NSImage(
                systemSymbolName: item.symbolName, accessibilityDescription: nil)
            // ⌘1–9 already select the first nine documents (AppDelegate's menu), so
            // showing the same digit here teaches the shortcut instead of hiding it.
            if index < 9 { entry.keyEquivalent = String(index + 1) }
            menu.addItem(entry)
        }
        // Below the chevron, left-aligned to it — where a popup button's menu appears.
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: overflowButtonRect.minX, y: overflowButtonRect.minY),
            in: self)
    }

    @objc private func overflowMenuDidPick(_ sender: NSMenuItem) {
        guard items.indices.contains(sender.tag) else { return }
        delegate?.tabStrip(self, didSelect: sender.tag)
    }
}

// MARK: - Accessibility elements

/// A weak handle on the strip, handed to every child element.
///
/// The strip owns its elements and the elements must call back into it, so one side
/// has to be weak. Doing it in one box rather than a `weak var` per element keeps
/// the ownership story in one place.
@MainActor
private final class TabStripAccessibilityBridge {
    weak var strip: DocumentTabStrip?
    init(strip: DocumentTabStrip) { self.strip = strip }
}

/// One tab, as VoiceOver sees it.
///
/// The overrides are `nonisolated` because AppKit's accessibility protocol is not
/// `@MainActor`-annotated in the SDK (`NSAccessibilityProtocols.h` carries no
/// `NS_SWIFT_UI_ACTOR`), so under Swift 6 a `@MainActor` override does not typecheck
/// against the inherited signature. `MainActor.assumeIsolated` re-establishes the
/// isolation for the body: the accessibility API is only ever driven from the main
/// thread, so this is the same trade `TerminalPane` makes with `@preconcurrency` on
/// its SwiftTerm conformance — a runtime check in place of a compile error, which is
/// the sanctioned path for an un-annotated dependency.
///
/// The item's values are copied in rather than read back through the bridge. An
/// element is rebuilt on every `reload`, so a copy cannot go stale, and reading
/// `items[index]` later is exactly how an element outlives the tab it describes and
/// starts index-crashing on a closed document.
@MainActor
private final class TabAccessibilityElement: NSAccessibilityElement {
    let index: Int
    private let bridge: TabStripAccessibilityBridge
    private let title: String
    private let isEdited: Bool
    private let position: Int
    private let total: Int
    private let isSelected: Bool

    init(
        bridge: TabStripAccessibilityBridge, index: Int, item: DocumentTabStrip.Item,
        position: Int, total: Int, isSelected: Bool
    ) {
        self.bridge = bridge
        self.index = index
        self.title = item.title
        self.isEdited = item.isEdited
        self.position = position
        self.total = total
        self.isSelected = isSelected
        super.init()
    }

    /// `.radioButton`, not `.button`: it is the role `NSTabViewItem` reports, and it
    /// is the one whose contract includes a selected/not-selected value, which is
    /// the whole point of vending these (`NSAccessibilityProtocols.h:54-61`).
    override nonisolated func accessibilityRole() -> NSAccessibility.Role? { .radioButton }

    override nonisolated func accessibilityRoleDescription() -> String? { "document tab" }

    /// Position is spoken because a tab group cannot convey "3 of 7" on its own when
    /// the children are synthesised, and the edited word is in the label rather than
    /// the value because the value slot is spoken for by the selection state that the
    /// radio-button role requires.
    override nonisolated func accessibilityLabel() -> String? {
        var parts = ["\(title), tab \(position) of \(total)"]
        if isEdited { parts.append("unsaved changes") }
        return parts.joined(separator: ", ")
    }

    override nonisolated func accessibilityValue() -> Any? { NSNumber(value: isSelected) }

    override nonisolated func isAccessibilitySelected() -> Bool { isSelected }

    override nonisolated func accessibilityPerformPress() -> Bool {
        let bridge = bridge
        let index = index
        return MainActor.assumeIsolated { bridge.strip?.accessibilitySelect(index: index) ?? false }
    }

    /// Closing is a custom action rather than `accessibilityPerformDelete` on purpose:
    /// VoiceOver surfaces custom actions by name in its actions menu (VO-Command-Space),
    /// so the user hears "Close Tab" instead of having to know that Delete is wired.
    override nonisolated func accessibilityCustomActions() -> [NSAccessibilityCustomAction] {
        [NSAccessibilityCustomAction(name: "Close Tab", target: self, selector: #selector(performClose))]
    }

    /// Kept as well, because VoiceOver's plain delete gesture is what some users
    /// reach for first and it costs one line to honour both.
    override nonisolated func accessibilityPerformDelete() -> Bool { performClose() }

    @objc private nonisolated func performClose() -> Bool {
        let bridge = bridge
        let index = index
        return MainActor.assumeIsolated { bridge.strip?.accessibilityClose(index: index) ?? false }
    }
}

/// The new-document and overflow buttons. Hand-drawn glyphs with no text, so
/// without this they are unlabelled rectangles that VoiceOver cannot even find.
///
/// Carries a `Kind` rather than a closure. A stored `() -> Bool` cannot be read from
/// the `nonisolated` override above — a function type is not `Sendable`, so the
/// compiler rejects reading it across the isolation boundary, while a `let` of a
/// `@MainActor` class (the bridge) is implicitly `Sendable` and can be. An enum plus
/// the same bridge also keeps both element kinds on one mechanism.
@MainActor
private final class ChromeAccessibilityElement: NSAccessibilityElement {
    enum Kind {
        case newDocument
        case overflow
    }

    private let bridge: TabStripAccessibilityBridge
    private let kind: Kind
    private let label: String
    private let help: String

    init(
        bridge: TabStripAccessibilityBridge, parent: NSView, frame: NSRect,
        kind: Kind, label: String, help: String
    ) {
        self.bridge = bridge
        self.kind = kind
        self.label = label
        self.help = help
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityFrameInParentSpace(frame)
    }

    override nonisolated func accessibilityRole() -> NSAccessibility.Role? { .button }
    override nonisolated func accessibilityLabel() -> String? { label }
    override nonisolated func accessibilityHelp() -> String? { help }
    override nonisolated func accessibilityPerformPress() -> Bool {
        let bridge = bridge
        let kind = kind
        return MainActor.assumeIsolated {
            guard let strip = bridge.strip else { return false }
            return strip.accessibilityPerformChrome(kind)
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
