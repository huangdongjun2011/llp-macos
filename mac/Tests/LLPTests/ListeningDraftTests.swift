import XCTest
@testable import LLPCore

final class ListeningDraftTests: XCTestCase {
    func testListeningEditorStartsHiddenAndEmpty() {
        let draft = ListeningDraft()

        XCTAssertFalse(draft.isEditorVisible)
        XCTAssertEqual(draft.text, "")
    }

    func testToggleEditorVisibilityOpensAndClosesEditor() {
        var draft = ListeningDraft()

        XCTAssertTrue(draft.toggleEditorVisibility())
        XCTAssertTrue(draft.isEditorVisible)

        XCTAssertFalse(draft.toggleEditorVisibility())
        XCTAssertFalse(draft.isEditorVisible)
    }

    func testTextIsPreservedWhenVisibilityChanges() {
        var draft = ListeningDraft(text: "heard phrase")

        draft.toggleEditorVisibility()
        draft.toggleEditorVisibility()

        XCTAssertEqual(draft.text, "heard phrase")
    }
}
