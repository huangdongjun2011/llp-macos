import XCTest
import HTTPTypes
import OpenAPIRuntime
@testable import LLPCore

final class TranscriptTests: XCTestCase {
    private let session = AuthSession(email: "a@example.com", deviceID: "device", accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)

    func testWireContractEmptyUnicodeAndEscapedKey() async throws {
        let transport = TranscriptTransport()
        let client = TranscriptClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: TranscriptStore(session: session), transport: transport))
        for text in ["", "你好\n\"transcript\"", String(repeating: "a", count: 65535)] {
            try await client.save(mediaKey: "a/b?c#d", session: session, transcript: text)
            let calls = await transport.calls
            let call = try XCTUnwrap(calls.last)
            XCTAssertEqual(call.0.method, .put)
            XCTAssertEqual(call.0.path, "/media-items/a%2Fb%3Fc%23d/transcript")
            XCTAssertEqual(call.0.headerFields[.authorization], "Bearer access")
            XCTAssertEqual(call.0.headerFields[.contentType], "application/json")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: call.1) as? [String: String], ["transcript": text])
        }
        do {
            try await client.save(mediaKey: "key", session: session, transcript: String(repeating: "你", count: 21846))
            XCTFail("Expected byte limit")
        } catch TranscriptError.tooLong { }
        let count = await transport.calls.count
        XCTAssertEqual(count, 3)
    }

    @MainActor func testEditorSavesWithoutListeningAutosave() async throws {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("media bytes".utf8).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        for url in [local, URL(string: "https://example.com/audio.mp3")!] {
            let transport = TranscriptTransport()
            let client = TranscriptClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: TranscriptStore(session: session), transport: transport))
            let editor = TranscriptEditor(service: client)
            editor.select(url: url, session: session)
            editor.text = "你好\ntranscript"
            await editor.save()
            XCTAssertEqual(editor.message, "Transcript saved.")
            XCTAssertFalse(editor.isSaving)
            let calls = await transport.calls
            XCTAssertEqual(calls.count, 1)
            let call = try XCTUnwrap(calls.first)
            let media = try DictationMedia.identify(url)
            XCTAssertEqual(call.0.path, "/media-items/\(media.key)/transcript")
            XCTAssertEqual(call.0.method, .put)
            XCTAssertEqual(call.0.headerFields[.authorization], "Bearer access")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: call.1) as? [String: Any])
            XCTAssertEqual(body["transcript"] as? String, editor.text)
            XCTAssertEqual(body["media"] as? [String: String], [
                "source_type": url.isFileURL ? "local" : "official",
                "media_type": url.isFileURL ? "video" : "audio"
            ])
        }
    }

    func testSessionBindingAndHTTPFailure() async throws {
        let transport = TranscriptTransport(status: 404)
        let store = TranscriptStore(session: session)
        let client = TranscriptClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: store, transport: transport))
        do {
            try await client.save(mediaKey: "key", session: session, transcript: "draft")
            XCTFail("Expected HTTP error")
        } catch APIClientError.http(let response, _) { XCTAssertEqual(response.status.code, 404) }
        store.data = nil
        do {
            try await client.save(mediaKey: "key", session: session, transcript: "draft")
            XCTFail("Expected authentication error")
        } catch APIClientError.loginRequired { }
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    @MainActor func testPrerequisitesFailureRetryAndSelectionReset() async {
        let service = TranscriptStub()
        let editor = TranscriptEditor(service: service)
        editor.text = "draft"
        await editor.save()
        XCTAssertTrue(service.texts.isEmpty)
        editor.select(url: URL(string: "https://example.com/a")!, session: nil)
        await editor.save()
        XCTAssertTrue(service.texts.isEmpty)
        editor.select(url: URL(string: "https://example.com/a")!, session: session)
        editor.text = String(repeating: "你", count: 21846)
        await editor.save()
        XCTAssertTrue(service.texts.isEmpty)
        editor.text = "draft"
        service.fail = true
        await editor.save()
        XCTAssertEqual(editor.text, "draft")
        XCTAssertFalse(editor.isSaving)
        XCTAssertTrue(editor.message.contains("No saved dictation"))
        service.fail = false
        await editor.save()
        XCTAssertEqual(service.texts, ["draft", "draft"])
        XCTAssertEqual(editor.message, "Transcript saved.")
        editor.text = ""
        await editor.save()
        XCTAssertEqual(service.texts.last, "")
        editor.select(url: nil, session: nil)
        XCTAssertEqual(editor.text, "")
        XCTAssertEqual(editor.message, "")
    }

    @MainActor func testDuplicateSaveAndStaleCompletion() async {
        let service = TranscriptStub()
        service.deferSave = true
        let editor = TranscriptEditor(service: service)
        editor.select(url: URL(string: "https://example.com/a")!, session: session)
        editor.text = "original"
        let task = Task { await editor.save() }
        await service.waitForSave()
        await editor.save()
        XCTAssertEqual(service.texts, ["original"])
        editor.select(url: URL(string: "https://example.com/b")!, session: session)
        editor.text = "new media"
        service.pending?.resume(); service.pending = nil
        await task.value
        XCTAssertEqual(editor.text, "new media")
        XCTAssertEqual(editor.message, "")
        XCTAssertFalse(editor.isSaving)
    }
}

private final class TranscriptStore: AuthStoring {
    var data: Data?
    init(session: AuthSession) { data = try! JSONEncoder().encode(AuthRecord(deviceID: "device", session: session)) }
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}
private actor TranscriptTransport: ClientTransport {
    let status: Int
    var calls: [(HTTPRequest, Data)] = []
    init(status: Int = 204) { self.status = status }
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let bytes = try await Data(collecting: body!, upTo: .max)
        calls.append((request, bytes))
        return (HTTPResponse(status: .init(code: status)), nil)
    }
}
@MainActor private final class TranscriptStub: TranscriptServing {
    var texts: [String] = []
    var fail = false
    var deferSave = false
    var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func waitForSave() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func save(media: DictationMedia, session: AuthSession, transcript: String) async throws {
        texts.append(transcript)
        if fail { throw APIClientError.http(HTTPResponse(status: .notFound), Data()) }
        if deferSave {
            await withCheckedContinuation {
                pending = $0
                started?.resume(); started = nil
            }
        }
    }
}
