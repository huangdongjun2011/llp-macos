import AppKit
import XCTest
@testable import LLP

@MainActor
final class ListeningTextUndoTests: XCTestCase {
    func testEditMenuProvidesResponderChainUndoAndRedo() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        AppDelegate().configureMainMenu()
        let editMenu = try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu).first { $0.title == "Edit" })
        let undo = try XCTUnwrap(editMenu.item(withTitle: "Undo"))
        let redo = try XCTUnwrap(editMenu.item(withTitle: "Redo"))
        XCTAssertEqual(undo.action, Selector(("undo:")))
        XCTAssertEqual(redo.action, Selector(("redo:")))
        XCTAssertEqual(undo.keyEquivalent, "z")
        XCTAssertEqual(redo.keyEquivalent, "z")
        XCTAssertEqual(undo.keyEquivalentModifierMask, .command)
        XCTAssertEqual(redo.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertNil(undo.target)
        XCTAssertNil(redo.target)
    }

    func testEditorUndoAndRedoActionsRestoreReplacement() throws {
        _ = NSApplication.shared
        let controller = PlayerViewController(playbackController: AVAudioPlaybackController())
        controller.loadView()
        let editor = try XCTUnwrap(descendant(NSTextView.self, in: controller.view))
        // A window supplies the editor's undo manager; global menu routing is
        // validated manually in the running app (see README).
        editor.removeFromSuperview()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.close() }
        XCTAssertTrue(editor.allowsUndo)
        let manager = try XCTUnwrap(editor.undoManager)
        manager.groupsByEvent = false
        manager.removeAllActions()
        XCTAssertFalse(manager.canUndo)
        editor.string = "hello world"
        editor.setSelectedRange(NSRange(location: 6, length: 5))
        manager.beginUndoGrouping()
        editor.insertText("reader", replacementRange: editor.selectedRange())
        editor.breakUndoCoalescing()
        manager.endUndoGrouping()
        XCTAssertEqual(editor.string, "hello reader")
        XCTAssertTrue(manager.canUndo)

        XCTAssertTrue(editor.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertEqual(editor.string, "hello world")
        XCTAssertTrue(manager.canRedo)
        XCTAssertTrue(editor.tryToPerform(Selector(("redo:")), with: nil))
        XCTAssertEqual(editor.string, "hello reader")

        XCTAssertTrue(editor.tryToPerform(Selector(("undo:")), with: nil))
        manager.beginUndoGrouping()
        editor.insertText("!", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        editor.breakUndoCoalescing()
        manager.endUndoGrouping()
        XCTAssertEqual(editor.string, "hello world!")
        XCTAssertFalse(manager.canRedo)
        XCTAssertTrue(editor.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertEqual(editor.string, "hello world")
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }
}
