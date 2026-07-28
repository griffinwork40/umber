//
//  SpaceViewController+Delegates.swift
//  Everything that reaches a Space from somewhere else: the four delegate conformances.
//
//  One concern, not four. Each of these is the same sentence — "the user did
//  something in another view (the file tree, the tab strip, a pane's shell) and the
//  container has to react" — and each one forwards straight into the document API in
//  `SpaceViewController.swift`. Splitting them apart would scatter one story across
//  four files; leaving them in the container buried its actual job under a hundred
//  lines of inbound plumbing.
//
//  Note that nothing here narrows `SpaceDocument` to a concrete kind. The
//  `TerminalPane` and `FileViewerPane` parameters are imposed by *those* panes' own
//  delegate protocols — they are the callback's signature, not a cast in the
//  container — so the document list stays kind-agnostic and a new conformer still
//  costs this file nothing (`SpaceDocument.swift`, plan §12.3).
//

import AppKit

// MARK: - FileViewerPaneDelegate

extension SpaceViewController: FileViewerPaneDelegate {
    func fileViewerDidChangeEditedState(_ pane: FileViewerPane) {
        // Repaint the strip so the unsaved dot appears/disappears as you type.
        syncStrip()
    }
}

// MARK: - DocumentTabStripDelegate

extension SpaceViewController: DocumentTabStripDelegate {
    func tabStrip(_ strip: DocumentTabStrip, didSelect index: Int) {
        selectDocument(at: index)
    }

    func tabStrip(_ strip: DocumentTabStrip, didRequestClose index: Int) {
        closeDocument(at: index)
    }

    func tabStripDidRequestNewDocument(_ strip: DocumentTabStrip) {
        addTerminalDocument()
    }
}

// MARK: - TerminalPaneDelegate

extension SpaceViewController: TerminalPaneDelegate {
    func paneDidTerminate(_ pane: TerminalPane) {
        // The shell exited — close that document specifically, not the active one:
        // a background tab's shell can exit while you are looking at another.
        guard let index = documents.firstIndex(where: { $0 === pane }) else { return }
        closeDocument(at: index)
    }

    func pane(_ pane: TerminalPane, didChangeTitle title: String) {
        syncStrip()
        guard documents.indices.contains(activeIndex), documents[activeIndex] === pane else { return }
        spaceDelegate?.spaceViewController(self, didChangeDocumentTitle: pane.documentTitle)
    }

    /// A background pane raised or cleared an attention marker. Only the strip cares —
    /// the window title stays the active document's, because a background tab beeping
    /// must not relabel the window you are working in.
    func paneDidChangeStatus(_ pane: TerminalPane) {
        syncStrip()
    }
}

// MARK: - FileTreeViewControllerDelegate

extension SpaceViewController: FileTreeViewControllerDelegate {
    /// Double-click opens the file in a document tab — what every Mac user already
    /// means by double-clicking a row in a file tree.
    ///
    /// This used to type the path into the terminal instead, because there was no
    /// document kind to open a file *into*. That was an honest placeholder and a
    /// bad feature: a picker whose only effect is inserting text reads as broken to
    /// anyone who did not write it. `FileViewerPane` gives the tree somewhere to go.
    func fileTree(_ controller: FileTreeViewController, didActivate url: URL) {
        openFile(url: url)
    }

    /// The old behaviour, kept and given a name.
    ///
    /// Inserting a quoted path is genuinely useful — it is what you want while
    /// composing `nvim <path>` or `git add <path>` — it was just bound to the one
    /// gesture that means "open". Now it is ⌥-double-click and a context-menu item,
    /// which also makes it discoverable, which it never was.
    func fileTree(_ controller: FileTreeViewController, didRequestPathInsert url: URL) {
        // A Space with zero terminal tabs (every document is a file viewer) has
        // nowhere for this to land — beep rather than silently doing nothing, so
        // the gesture doesn't read as broken (PR #2 review, finding 5).
        guard let pane = focusedTerminalPane else {
            NSSound.beep()
            return
        }
        // Single-quoted, with any embedded quote closed-escaped-reopened, so spaces,
        // `$`, and quotes in a filename survive the shell verbatim.
        let quoted = "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        pane.view.send(txt: quoted + " ")
        // Bring the terminal forward if a viewer was in front, otherwise the text
        // lands in a tab the user cannot see.
        if let index = documents.firstIndex(where: { $0 === pane }), index != activeIndex {
            selectDocument(at: index)
        } else {
            pane.documentDidBecomeActive()
        }
    }

    /// "New Terminal Here" — the other half of rooting terminals properly.
    ///
    /// ⌘T uses the Space's root; this uses the directory you clicked, which is what
    /// you want the moment a project is more than one directory deep. `url` is already
    /// resolved to a directory by the tree (`FileTreeViewController.menuNewTerminal`),
    /// so there is deliberately no file/folder branch here.
    ///
    /// A new document every time rather than reusing an existing terminal on that
    /// path, which is the opposite of `openFile(url:)`'s reuse rule — and the
    /// difference is real, not an inconsistency: two viewers of one file show the same
    /// bytes twice, while two shells in one directory are two independent sessions
    /// (one running a server, one running git) and collapsing them would destroy work.
    func fileTree(_ controller: FileTreeViewController, didRequestNewTerminalAt url: URL) {
        addTerminalDocument(workingDirectory: url)
    }
}
