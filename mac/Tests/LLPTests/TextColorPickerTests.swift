import AppKit
import XCTest
@testable import LLP

@MainActor
final class TextColorPickerTests: XCTestCase {
    func testDefaultsAndExclusiveSelectionIncludingRepeatedClick() {
        let picker = TextColorPicker()
        XCTAssertEqual(picker.circles.count, 3)
        XCTAssertEqual(picker.circles.map(\.color), [.red, .black, .green])
        XCTAssertEqual(picker.circles.map(\.state), [.off, .on, .off])
        var received: [NSColor] = []
        picker.onColorSelected = { received.append($0) }
        for index in [0, 0, 2, 1] {
            picker.circles[index].performClick(nil)
            XCTAssertEqual(picker.selectedIndex, index)
            XCTAssertEqual(picker.circles.filter { $0.state == .on }.count, 1)
            XCTAssertEqual(picker.circles[index].state, .on)
        }
        XCTAssertEqual(received, [.red, .red, .green, .black])
    }

    func testDoubleClickOffersTwelveColorsAndReplacementChangesOnlyTarget() {
        let picker = TextColorPicker()
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 2, pressure: 1
        )!
        picker.circles[2].mouseDown(with: event)
        XCTAssertEqual(picker.editingIndex, 2)
        XCTAssertEqual(picker.paletteButtons.count, 12)
        XCTAssertEqual(picker.paletteButtons.map(\.color), TextColorPicker.palette.map(\.color))
        var applied: NSColor?
        picker.onColorSelected = { applied = $0 }
        picker.paletteButtons[3].performClick(nil)
        XCTAssertEqual(picker.circles.map(\.color), [.red, .black, .blue])
        XCTAssertEqual(picker.circles.map(\.state), [.off, .off, .on])
        XCTAssertEqual(applied, .blue)
        XCTAssertNil(picker.editingIndex)
        // A stale palette action cannot replace another favorite.
        picker.paletteButtons[4].performClick(nil)
        XCTAssertEqual(picker.circles[2].color, .blue)
    }

    func testEveryPaletteChoiceAndEveryFavoriteCanBeUsed() {
        let picker = TextColorPicker()
        for slot in 0..<3 {
            for choice in TextColorPicker.palette.indices {
                picker.showPalette(for: slot)
                picker.paletteButtons[choice].performClick(nil)
                XCTAssertEqual(picker.circles[slot].color, TextColorPicker.palette[choice].color)
                XCTAssertEqual(picker.circles.filter { $0.state == .on }.count, 1)
            }
        }
        picker.showPalette(for: -1)
        picker.showPalette(for: 3)
        XCTAssertNil(picker.editingIndex)
    }

    func testClosingPaletteWithoutChoosingPreservesFavoriteColors() {
        let picker = TextColorPicker()
        picker.showPalette(for: 0)
        picker.popover.close()
        XCTAssertEqual(picker.circles.map(\.color), [.red, .black, .green])
        XCTAssertEqual(picker.circles.map(\.state), [.on, .off, .off])
    }

    func testPlayerAppliesFavoriteAndReplacementToSelectionAndTyping() throws {
        // loadView builds the real formatting controls without starting authentication.
        let controller = PlayerViewController(playbackController: AVAudioPlaybackController())
        controller.loadView()
        let picker = try XCTUnwrap(descendant(TextColorPicker.self, in: controller.view))
        let editor = try XCTUnwrap(descendant(NSTextView.self, in: controller.view))
        let font = NSFont.boldSystemFont(ofSize: 19)
        editor.textStorage?.setAttributedString(NSAttributedString(
            string: "hello world", attributes: [.foregroundColor: NSColor.black, .font: font,
                                                 .strikethroughStyle: 1]
        ))
        editor.setSelectedRange(NSRange(location: 0, length: 5))
        picker.circles[0].performClick(nil)
        XCTAssertEqual(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .red)
        XCTAssertEqual(editor.textStorage?.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor, .black)
        XCTAssertEqual(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, font)
        XCTAssertEqual(editor.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int, 1)
        picker.showPalette(for: 0)
        picker.paletteButtons[3].performClick(nil)
        XCTAssertEqual(editor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .blue)
        editor.setSelectedRange(NSRange(location: 11, length: 0))
        picker.circles[2].performClick(nil)
        XCTAssertEqual(editor.typingAttributes[.foregroundColor] as? NSColor, .green)
        XCTAssertEqual(editor.textStorage?.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor, .black)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = descendant(type, in: child) { return match }
        }
        return nil
    }
}
