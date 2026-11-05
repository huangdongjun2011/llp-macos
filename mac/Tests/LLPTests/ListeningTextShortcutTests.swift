import XCTest
@testable import LLPCore

final class ListeningTextShortcutTests: XCTestCase {
    private let resolver = ListeningTextShortcutResolver()

    func testCommandTextShortcutsPerformEditingActions() {
        XCTAssertEqual(action(for: "a", command: true), .selectAll)
        XCTAssertEqual(action(for: "c", command: true), .copy)
        XCTAssertEqual(action(for: "v", command: true), .paste)
    }

    func testOptionTextShortcutsPassThrough() {
        XCTAssertEqual(action(for: "c", option: true), .passThrough)
        XCTAssertEqual(action(for: "v", option: true), .passThrough)
    }

    func testOptionAStartMarkerShortcutPassesThroughTextEditor() {
        XCTAssertEqual(action(for: "a", option: true), .passThrough)
        XCTAssertEqual(action(for: "A", option: true), .passThrough)
        XCTAssertEqual(action(for: "a", command: true), .selectAll)
    }

    func testOptionEEndMarkerShortcutPassesThroughTextEditor() {
        XCTAssertEqual(action(for: "e", option: true), .passThrough)
        XCTAssertEqual(action(for: "E", option: true), .passThrough)
    }

    func testOptionDNextSegmentShortcutPassesThroughTextEditor() {
        XCTAssertEqual(action(for: "d", option: true), .passThrough)
        XCTAssertEqual(action(for: "D", option: true), .passThrough)
    }

    func testOptionRReplaySegmentShortcutPassesThroughTextEditor() {
        XCTAssertEqual(action(for: "r", option: true), .passThrough)
        XCTAssertEqual(action(for: "R", option: true), .passThrough)
    }

    func testNonTextShortcutKeysPassThrough() {
        XCTAssertEqual(action(for: "x", option: true), .passThrough)
        XCTAssertEqual(action(for: nil, option: true), .passThrough)
    }

    func testShortcutKeysWithAdditionalModifiersPassThrough() {
        XCTAssertEqual(action(for: "a", option: true, shift: true), .passThrough)
        XCTAssertEqual(action(for: "c", option: true, command: true), .passThrough)
        XCTAssertEqual(action(for: "v", command: true, control: true), .passThrough)
    }

    func testShortcutKeysWithoutOptionOrCommandPassThrough() {
        XCTAssertEqual(action(for: "a"), .passThrough)
        XCTAssertEqual(action(for: "c", control: true), .passThrough)
        XCTAssertEqual(action(for: "v", shift: true), .passThrough)
    }

    private func action(
        for key: String?,
        option: Bool = false,
        command: Bool = false,
        control: Bool = false,
        shift: Bool = false
    ) -> ListeningTextShortcutAction {
        resolver.action(
            for: key,
            hasOption: option,
            hasCommand: command,
            hasControl: control,
            hasShift: shift
        )
    }
}
