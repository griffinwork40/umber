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

    private static let minTabWidth: CGFloat = 96
    private static let maxTabWidth: CGFloat = 210
    private static let newButtonWidth: CGFloat = 30
    private static let closeBoxSide: CGFloat = 15
    private static let horizontalPadding: CGFloat = 8

    weak var delegate: DocumentTabStripDelegate?

    private var items: [Item] = []
    private var activeIndex: Int = 0
    private var hoveredTab: Int?
    private var hoveredClose: Int?
    private var isHoveringNewButton = false

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

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return 0 }
        let available = max(bounds.width - Self.newButtonWidth, 0)
        let even = available / CGFloat(items.count)
        return min(max(even, Self.minTabWidth), Self.maxTabWidth)
    }

    private func tabRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height)
    }

    private func closeRect(_ index: Int) -> NSRect {
        let tab = tabRect(index)
        return NSRect(
            x: tab.maxX - Self.horizontalPadding - Self.closeBoxSide,
            y: (tab.height - Self.closeBoxSide) / 2,
            width: Self.closeBoxSide,
            height: Self.closeBoxSide
        )
    }

    private var newButtonRect: NSRect {
        NSRect(
            x: CGFloat(items.count) * tabWidth, y: 0,
            width: Self.newButtonWidth, height: bounds.height
        )
    }

    private func tabIndex(at point: NSPoint) -> Int? {
        guard tabWidth > 0 else { return nil }
        let index = Int(point.x / tabWidth)
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

        for index in items.indices {
            drawTab(index)
        }
        drawNewButton()

        // Hairline under the *inactive* stretch only. Running it under the active
        // tab too would draw a line between the tab and its own content, which is
        // precisely the seam this design removes.
        contentForeground.withAlphaComponent(0.12).setFill()
        let hairline = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        let active = tabRect(activeIndex)
        for slice in hairline.slices(excluding: items.indices.contains(activeIndex) ? active : .zero) {
            slice.fill()
        }
    }

    private func drawTab(_ index: Int) {
        let rect = tabRect(index)
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
        // Only repaint on an actual state change: mouseMoved fires continuously,
        // and the terminal underneath deserves the frames more than this rail does.
        guard tab != hoveredTab || close != hoveredClose || newButton != isHoveringNewButton
        else { return }
        hoveredTab = tab
        hoveredClose = close
        isHoveringNewButton = newButton
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTab = nil
        hoveredClose = nil
        isHoveringNewButton = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if newButtonRect.contains(point) {
            delegate?.tabStripDidRequestNewDocument(self)
            return
        }
        guard let index = tabIndex(at: point) else { return }
        // Close wins over select: the × sits inside the tab's own rect, so testing
        // it second would select the tab and never close it.
        if (index == activeIndex || hoveredTab == index), closeRect(index).contains(point) {
            delegate?.tabStrip(self, didRequestClose: index)
        } else {
            delegate?.tabStrip(self, didSelect: index)
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
