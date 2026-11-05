import XCTest
import ImageIO
import UniformTypeIdentifiers
import HTTPTypes
import OpenAPIRuntime
@testable import LLPCore

final class TranscriptOCRTests: XCTestCase {
    private let session = AuthSession(email: "a@example.com", deviceID: "device", accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)

    func testWireContractAndValidation() async throws {
        let transport = OCRTransport()
        let client = TranscriptOCRClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: OCRStore(session), transport: transport))
        let text = try await client.recognize(image: Data([1, 2, 3]), contentType: "image/png", session: session)
        XCTAssertEqual(text, "你好\ntext")
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0.path, "/transcripts/ocr")
        XCTAssertEqual(calls.first?.0.method, .post)
        XCTAssertEqual(calls.first?.0.headerFields[.authorization], "Bearer access")
        XCTAssertEqual(calls.first?.0.headerFields[.contentType], "image/png")
        XCTAssertEqual(calls.first?.1, Data([1, 2, 3]))
        for data in [Data(), Data(repeating: 0, count: 5_000_000), Data(repeating: 0, count: 5_000_001)] {
            do { _ = try await client.recognize(image: data, contentType: "image/png", session: session); XCTFail("Expected size rejection") }
            catch TranscriptOCRError.invalidImage { }
        }
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testImagePreparationSizeBoundaries() throws {
        let allowed = Data(repeating: 1, count: 4_999_999)
        XCTAssertEqual(try TranscriptOCRImage.prepare(allowed, contentType: "image/png").data, allowed)
        for data in [Data(), Data(repeating: 0, count: 5_000_000), Data(repeating: 0, count: 5_000_001)] {
            XCTAssertThrowsError(try TranscriptOCRImage.prepare(data, contentType: "image/png"))
        }
        XCTAssertThrowsError(try TranscriptOCRImage.prepare(Data([1, 2, 3]), contentType: "image/heic"))
    }

    // Native ImageIO integration: no GUI runtime or network is required.
    func testHEICConversionProducesJPEG() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        for type in ["image/heic", "image/heif"] {
            let prepared = try TranscriptOCRImage.prepare(encoded as Data, contentType: type)
            XCTAssertEqual(prepared.contentType, "image/jpeg")
            XCTAssertLessThan(prepared.data.count, 5_000_000)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, 16)
            XCTAssertEqual(decoded.height, 32)
        }
    }

    func testHTTPAndInvalidResponse() async throws {
        for (status, body) in [(504, "{}"), (200, "{}"), (200, "{\"transcript\":\"\"}")] {
            let transport = OCRTransport(status: status, response: body)
            let client = TranscriptOCRClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: OCRStore(session), transport: transport))
            do { _ = try await client.recognize(image: Data([1]), contentType: "image/png", session: session); XCTFail("Expected error") }
            catch { }
        }
    }

    @MainActor func testBackendErrorMessagesPreserveDraft() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let service = OCRStub()
        let editor = TranscriptEditor(service: OCRSaveStub(), ocr: service)
        editor.select(url: url, session: session)
        editor.text = "draft"
        let cases: [(Int, String)] = [
            (400, "Image is empty"),
            (413, "Image must be smaller than 5 MB"),
            (415, "Image content does not match its type"),
            (422, "No text found in image"),
            (422, "Recognized transcript exceeds 65535 UTF-8 bytes"),
            (502, "Could not recognize image"),
            (503, "Image text recognition is unavailable"),
            (504, "Image text recognition timed out")
        ]
        var responses = try cases.map { status, message in
            (status, try JSONEncoder().encode(["message": message]), "\(message). Your draft is kept.")
        }
        for body in ["not JSON", "{}", "{\"message\":\"   \"}"] {
            responses.append((503, Data(body.utf8), "Image recognition failed (HTTP 503). Your draft is kept; try again."))
        }
        for (status, body, expected) in responses {
            let upload = Task { await editor.upload(url: url, contentType: "image/png") }
            await service.waitForStart()
            service.pending?.resume(throwing: APIClientError.http(HTTPResponse(status: .init(code: status)), body))
            service.pending = nil
            await upload.value
            XCTAssertEqual(editor.message, expected)
            XCTAssertEqual(editor.text, "draft")
            XCTAssertFalse(editor.isUploading)
        }
    }

    @MainActor func testFailedConversionDoesNotShowBackendStage() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for type in ["image/heic", "image/heif"] {
            let service = OCRStub()
            let editor = TranscriptEditor(service: OCRSaveStub(), ocr: service)
            editor.select(url: url, session: session)
            editor.text = "draft"
            var messages: [String] = []
            editor.onChange = { messages.append(editor.message) }
            await editor.upload(url: url, contentType: type)
            XCTAssertEqual(messages.first, "Transforming image…")
            XCTAssertFalse(messages.contains("Translating image…"))
            XCTAssertEqual(service.calls, 0)
            XCTAssertEqual(editor.text, "draft")
            XCTAssertFalse(editor.isUploading)
            editor.onChange = {}
        }
    }

    @MainActor func testDraftReviewFailureAndStaleCompletion() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let service = OCRStub()
        let editor = TranscriptEditor(service: OCRSaveStub(), ocr: service)
        editor.select(url: url, session: session)
        editor.text = "draft"
        var messages: [String] = []
        editor.onChange = { messages.append(editor.message) }
        defer { editor.onChange = {} }
        let upload = Task { await editor.upload(url: url, contentType: "image/png") }
        await service.waitForStart()
        XCTAssertTrue(editor.isUploading)
        XCTAssertEqual(messages, ["Preparing image…", "Translating image…"])
        XCTAssertEqual(editor.message, "Translating image…")
        await editor.upload(url: url, contentType: "image/png")
        XCTAssertEqual(service.calls, 1)
        service.pending?.resume(returning: "recognized"); service.pending = nil
        await upload.value
        XCTAssertEqual(editor.text, "recognized")
        XCTAssertFalse(editor.isUploading)
        XCTAssertTrue(editor.message.contains("Review"))

        let failure = Task { await editor.upload(url: url, contentType: "image/png") }
        await service.waitForStart()
        service.pending?.resume(throwing: URLError(.timedOut)); service.pending = nil
        await failure.value
        XCTAssertEqual(editor.text, "recognized")
        XCTAssertTrue(editor.message.contains("timed out"))
        XCTAssertFalse(editor.isUploading)

        let stale = Task { await editor.upload(url: url, contentType: "image/png") }
        await service.waitForStart()
        editor.select(url: nil, session: nil)
        editor.text = "new draft"
        service.pending?.resume(returning: "stale"); service.pending = nil
        await stale.value
        XCTAssertEqual(editor.text, "new draft")
        XCTAssertEqual(editor.message, "")
    }
}
private final class OCRStore: AuthStoring {
    var data: Data?
    init(_ session: AuthSession) { data = try! JSONEncoder().encode(AuthRecord(deviceID: "device", session: session)) }
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}
private actor OCRTransport: ClientTransport {
    var calls: [(HTTPRequest, Data)] = []
    let status: Int
    let response: String
    init(status: Int = 200, response: String = "{\"transcript\":\"你好\\ntext\"}") { self.status = status; self.response = response }
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        calls.append((request, try await Data(collecting: body!, upTo: .max)))
        return (HTTPResponse(status: .init(code: status)), HTTPBody(Data(response.utf8)))
    }
}
private struct OCRSaveStub: TranscriptServing {
    func save(media: DictationMedia, session: AuthSession, transcript: String) async throws { XCTFail("OCR must not save") }
}
@MainActor private final class OCRStub: TranscriptOCRServing {
    var calls = 0
    var pending: CheckedContinuation<String, Error>?
    var started: CheckedContinuation<Void, Never>?
    func waitForStart() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func recognize(image: Data, contentType: String, session: AuthSession) async throws -> String {
        calls += 1
        return try await withCheckedThrowingContinuation {
            pending = $0; started?.resume(); started = nil
        }
    }
}
