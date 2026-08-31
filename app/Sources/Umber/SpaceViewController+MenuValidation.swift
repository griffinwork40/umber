//
//  SpaceViewController+MenuValidation.swift
//  Menu-item enable/disable for the split and focus commands.
//
//  Its own file because `SpaceViewController.swift` hit the 350-line ceiling and
//  this is a clean seam: `validateUserInterfaceItem(_:)` is one whole concern —
//  "which menu items make sense given the current document and split state?" —
//  and it needs nothing from the container except read access to `activeDocument`
//  and `hasSplit`, both already internal.
//
//  Without this override, AppKit auto-enables every item whose @objc selector is
//  answered anywhere in the responder chain, even when the action would silently
//  no-op (e.g. opening a second split when one already exists).
//

import AppKit

@MainActor
extension SpaceViewController {
    /// Gate split/focus menu items — without this, AppKit auto-enables every item whose
    /// @objc selector is answered, even when the action would silently no-op.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(splitHorizontal(_:)):
            guard let doc = activeDocument else { return false }
            return doc is ShellHosting && !hasSplit(for: doc)
        case #selector(splitVertical(_:)):
            guard let doc = activeDocument else { return false }
            return doc is ShellHosting && !hasSplit(for: doc)
        case #selector(moveFocusLeft(_:)), #selector(moveFocusRight(_:)),
             #selector(moveFocusUp(_:)), #selector(moveFocusDown(_:)):
            return activeDocument.map { hasSplit(for: $0) } ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
