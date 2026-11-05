import AppKit
import XCTest
@testable import LLPCore

final class ListeningTextDocumentTests: XCTestCase {
    func testPersistenceRoundTripAndLegacyContent() throws {
        for text in ["", "plain notes", "今日は🙂", #"{"version":1,"text":"literal JSON","spans":[]}"#] {
            XCTAssertEqual(try ListeningTextDocument.fromPersistenceContent(text), ListeningTextDocument(text: text))
        }
        let document = ListeningTextDocument(text: "🙂red", spans: [
            .init(start: 2, length: 3, attributes: .init(foregroundColor: "#FF0000"))
        ])
        let content = try document.persistenceContent()
        XCTAssertEqual(try document.persistenceContent(), content)
        XCTAssertEqual(try ListeningTextDocument.fromPersistenceContent(content), document)
        XCTAssertEqual(try ListeningTextDocument.fromPersistenceContent(ListeningTextDocument(text: "").persistenceContent()).text, "")
    }

    func testPersistenceRejectsInvalidDocuments() {
        for json in [
            "{broken",
            #"{"version":2,"text":"x","spans":[]}"#,
            #"{"version":1,"text":"x","spans":[{"start":0,"length":2,"attributes":{}}]}"#,
            #"{"version":1,"text":"x","spans":[{"start":0,"length":1,"attributes":{"foregroundColor":"red"}}]}"#
        ] {
            XCTAssertThrowsError(try ListeningTextDocument.fromPersistenceContent("LLPListeningTextDocument\n" + json))
        }
    }

    func testDocumentEncodesReadableJsonFormat() throws {
        let document = ListeningTextDocument(
            text: "今日は日本の経済について勉強します。",
            spans: [
                .init(start: 3, length: 2, attributes: .init(bold: true)),
                .init(start: 6, length: 2, attributes: .init(foregroundColor: "#FF0000")),
                .init(start: 12, length: 6, attributes: .init(strikethrough: true))
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(data: try encoder.encode(document), encoding: .utf8)

        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("\"version\" : 1") == true)
        XCTAssertTrue(json?.contains("\"text\" : \"今日は日本の経済について勉強します。\"") == true)
        XCTAssertTrue(json?.contains("\"foregroundColor\" : \"#FF0000\"") == true)
        XCTAssertTrue(json?.contains("\"strikethrough\" : true") == true)
    }

    func testAttributedStringRoundTripsSupportedFormatting() throws {
        let source = NSMutableAttributedString(string: "heard phrase")
        source.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.red,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ], range: NSRange(location: 0, length: 5))

        let document = ListeningTextDocument(attributedString: source)
        let restored = try document.makeAttributedString()
        let restoredAttributes = restored.attributes(at: 0, effectiveRange: nil)

        XCTAssertEqual(restored.string, "heard phrase")
        XCTAssertEqual(document.spans.count, 1)
        XCTAssertEqual(document.spans[0].start, 0)
        XCTAssertEqual(document.spans[0].length, 5)
        XCTAssertEqual(document.spans[0].attributes.bold, true)
        XCTAssertEqual(document.spans[0].attributes.foregroundColor, "#FF0000")
        XCTAssertEqual(document.spans[0].attributes.strikethrough, true)
        XCTAssertEqual(document.spans[0].attributes.fontSize, 18)
        XCTAssertEqual(restoredAttributes[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual((restoredAttributes[.font] as? NSFont)?.pointSize, 18)
    }

    func testValidationUsesUtf16LengthForJapaneseAndEmojiText() throws {
        let document = ListeningTextDocument(
            text: "今日は🙂",
            spans: [
                .init(start: 2, length: 3, attributes: .init(strikethrough: true))
            ]
        )

        XCTAssertNoThrow(try document.validate())
    }

    func testMakeAttributedStringRejectsOutOfBoundsSpan() {
        let document = ListeningTextDocument(
            text: "short",
            spans: [
                .init(start: 4, length: 2, attributes: .init(foregroundColor: "#FF0000"))
            ]
        )

        XCTAssertThrowsError(try document.makeAttributedString()) { error in
            XCTAssertEqual(
                error as? ListeningTextDocumentError,
                .spanOutOfBounds(start: 4, length: 2, textLength: 5)
            )
        }
    }

    func testMakeAttributedStringRejectsInvalidColor() {
        let document = ListeningTextDocument(
            text: "color",
            spans: [
                .init(start: 0, length: 5, attributes: .init(foregroundColor: "red"))
            ]
        )

        XCTAssertThrowsError(try document.makeAttributedString()) { error in
            XCTAssertEqual(error as? ListeningTextDocumentError, .invalidForegroundColor("red"))
        }
    }
}
