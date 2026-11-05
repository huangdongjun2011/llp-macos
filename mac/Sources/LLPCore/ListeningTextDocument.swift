import AppKit
import Foundation

public struct ListeningTextDocument: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var text: String
    public var spans: [Span]

    public init(version: Int = currentVersion, text: String, spans: [Span] = []) {
        self.version = version
        self.text = text
        self.spans = spans
    }

    public init(attributedString: NSAttributedString) {
        self.version = Self.currentVersion
        self.text = attributedString.string

        var spans: [Span] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let spanAttributes = SpanAttributes(attributes: attributes)
            guard !spanAttributes.isEmpty, range.length > 0 else { return }

            spans.append(Span(
                start: range.location,
                length: range.length,
                attributes: spanAttributes
            ))
        }
        self.spans = spans
    }

    // A marker distinguishes rich content from legacy plain text (including JSON notes).
    private static let persistencePrefix = "LLPListeningTextDocument\n"

    public func persistenceContent() throws -> String {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return Self.persistencePrefix + String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func fromPersistenceContent(_ content: String) throws -> Self {
        guard content.hasPrefix(persistencePrefix) else {
            return Self(text: content)
        }
        let document = try JSONDecoder().decode(Self.self, from: Data(content.dropFirst(persistencePrefix.count).utf8))
        try document.validate()
        return document
    }

    public func makeAttributedString() throws -> NSAttributedString {
        try validate()

        let attributedString = NSMutableAttributedString(string: text)
        for span in spans where span.length > 0 {
            attributedString.addAttributes(
                try span.attributes.nsAttributes(),
                range: NSRange(location: span.start, length: span.length)
            )
        }
        return attributedString
    }

    public func validate() throws {
        guard version == Self.currentVersion else {
            throw ListeningTextDocumentError.unsupportedVersion(version)
        }

        let textLength = (text as NSString).length
        for span in spans {
            guard span.start >= 0, span.length >= 0 else {
                throw ListeningTextDocumentError.invalidSpan(start: span.start, length: span.length)
            }

            guard span.start <= textLength, span.length <= textLength - span.start else {
                throw ListeningTextDocumentError.spanOutOfBounds(
                    start: span.start,
                    length: span.length,
                    textLength: textLength
                )
            }

            if let foregroundColor = span.attributes.foregroundColor {
                guard NSColor(hexString: foregroundColor) != nil else {
                    throw ListeningTextDocumentError.invalidForegroundColor(foregroundColor)
                }
            }
        }
    }

    public struct Span: Codable, Equatable {
        public var start: Int
        public var length: Int
        public var attributes: SpanAttributes

        public init(start: Int, length: Int, attributes: SpanAttributes) {
            self.start = start
            self.length = length
            self.attributes = attributes
        }
    }

    public struct SpanAttributes: Codable, Equatable {
        public var bold: Bool?
        public var foregroundColor: String?
        public var strikethrough: Bool?
        public var fontSize: Double?

        public init(
            bold: Bool? = nil,
            foregroundColor: String? = nil,
            strikethrough: Bool? = nil,
            fontSize: Double? = nil
        ) {
            self.bold = bold
            self.foregroundColor = foregroundColor
            self.strikethrough = strikethrough
            self.fontSize = fontSize
        }

        public var isEmpty: Bool {
            bold == nil && foregroundColor == nil && strikethrough == nil && fontSize == nil
        }

        fileprivate init(attributes: [NSAttributedString.Key: Any]) {
            bold = nil
            foregroundColor = nil
            strikethrough = nil
            fontSize = nil

            let font = attributes[.font] as? NSFont
            if let font, NSFontManager.shared.traits(of: font).contains(.boldFontMask) {
                bold = true
            }
            if let font {
                fontSize = Double(font.pointSize)
            }
            if let color = attributes[.foregroundColor] as? NSColor {
                foregroundColor = color.hexString
            }
            if let style = attributes[.strikethroughStyle] as? Int, style != 0 {
                strikethrough = true
            }
        }

        fileprivate func nsAttributes() throws -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if bold == true || fontSize != nil {
                let size = CGFloat(fontSize ?? NSFont.systemFontSize)
                let baseFont = NSFont.systemFont(ofSize: size)
                attributes[.font] = bold == true
                    ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                    : baseFont
            }
            if let foregroundColor {
                guard let color = NSColor(hexString: foregroundColor) else {
                    throw ListeningTextDocumentError.invalidForegroundColor(foregroundColor)
                }
                attributes[.foregroundColor] = color
            }
            if strikethrough == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            return attributes
        }
    }
}

public enum ListeningTextDocumentError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidSpan(start: Int, length: Int)
    case spanOutOfBounds(start: Int, length: Int, textLength: Int)
    case invalidForegroundColor(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported listening text version: \(version)."
        case let .invalidSpan(start, length):
            "Invalid listening text span: start \(start), length \(length)."
        case let .spanOutOfBounds(start, length, textLength):
            "Listening text span \(start)..<\(start + length) is outside text length \(textLength)."
        case let .invalidForegroundColor(color):
            "Invalid listening text foreground color: \(color)."
        }
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        guard hexString.count == 7, hexString.first == "#" else { return nil }

        let startIndex = hexString.index(after: hexString.startIndex)
        let hex = String(hexString[startIndex...])
        guard let value = UInt32(hex, radix: 16) else { return nil }

        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
