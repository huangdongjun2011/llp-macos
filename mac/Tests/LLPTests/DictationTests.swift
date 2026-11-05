import AppKit
import XCTest
import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import LLPCore

final class DictationTests: XCTestCase {
    @MainActor func testColorOnlyEditSavesAndRestoresThroughPersistence() async throws {
        let service = Stub()
        let model = DictationPersistence(service: service)
        var editor = NSAttributedString(string: "")
        model.readText = { try ListeningTextDocument(attributedString: editor).persistenceContent() }
        model.restore = { content, _ in
            editor = try ListeningTextDocument.fromPersistenceContent(content).makeAttributedString()
        }
        let url = URL(string: "https://example.com/audio")!
        model.select(url: url, session: session())
        await model.playbackStarted()
        await model.tick()
        XCTAssertTrue(service.saves.isEmpty, "Loading legacy text must not cause an autosave")

        let colored = NSMutableAttributedString(attributedString: editor)
        colored.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 1, length: 3))
        editor = colored
        await model.tick()
        await model.tick()
        XCTAssertEqual(service.saves.count, 1, "A color-only change must save exactly once")
        service.content = try XCTUnwrap(service.saves.last?.0)
        model.select(url: url, session: session())
        await model.playbackStarted()
        XCTAssertEqual(editor.string, "saved")
        let restored = ListeningTextDocument(attributedString: editor)
        XCTAssertEqual(restored.spans.first?.attributes.foregroundColor, "#FF0000")
        XCTAssertEqual(restored.spans.first?.start, 1)
        XCTAssertEqual(restored.spans.first?.length, 3)
        XCTAssertNil(editor.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        await model.tick()
        XCTAssertEqual(service.saves.count, 1)
    }

    @MainActor func testFormattingEditDuringLoadIsPreserved() async throws {
        let service = DeferredService()
        let model = DictationPersistence(service: service)
        var document = ListeningTextDocument(text: "")
        model.readText = { try document.persistenceContent() }
        model.restore = { content, _ in document = try ListeningTextDocument.fromPersistenceContent(content) }
        model.select(url: URL(string: "https://example.com/audio")!, session: session())
        document = ListeningTextDocument(text: "draft")
        let load = Task { await model.playbackStarted() }
        await service.waitUntilLoading()
        document.spans = [.init(start: 0, length: 5, attributes: .init(foregroundColor: "#FF0000"))]
        let edited = document
        service.complete()
        await load.value
        XCTAssertEqual(document, edited)
    }

    @MainActor func testEncodingFailureDoesNotSaveAndCanRetry() async {
        let service = Stub()
        let model = DictationPersistence(service: service)
        model.select(url: URL(string: "https://example.com/audio")!, session: session())
        await model.playbackStarted()
        var errors = 0
        model.onError = { errors += 1 }
        model.readText = { throw ListeningTextDocumentError.invalidForegroundColor("bad") }
        await model.tick()
        XCTAssertEqual(errors, 1)
        XCTAssertTrue(service.saves.isEmpty)
        model.readText = { "edited" }
        await model.tick()
        XCTAssertEqual(service.saves.last?.0, "edited")
    }

    @MainActor func testInvalidRichContentBlocksOverwriteAndAllowsRetry() async throws {
        let service = Stub()
        service.content = "LLPListeningTextDocument\n{broken"
        let model = DictationPersistence(service: service)
        var errors = 0
        model.onError = { errors += 1 }
        model.readText = { "local edit" }
        model.select(url: URL(string: "https://example.com/audio")!, session: session())
        await model.playbackStarted()
        await model.tick()
        XCTAssertEqual(errors, 1)
        XCTAssertTrue(service.saves.isEmpty)
        service.content = "valid legacy text"
        await model.playbackStarted()
        XCTAssertEqual(service.loads, 2)
    }

    func testTranscriptDecoding() throws {
        for (field, expected) in [("", nil), (",\"transcript\":null", nil),
                                  (",\"transcript\":\"\"", ""),
                                  (",\"transcript\":\"saved transcript\"", "saved transcript")] {
            let json = "{\"content\":\"notes\",\"position_ms\":0,\"updated_at\":\"now\"\(field)}"
            let saved = try JSONDecoder().decode(Dictation.self, from: Data(json.utf8))
            XCTAssertEqual(saved.transcript, expected)
        }
    }

    @MainActor func testTranscriptRestorePreservesEditsDuringLoad() async {
        for edited in [false, true] {
            let service = DeferredService()
            let model = DictationPersistence(service: service)
            var transcript = "previous selection"
            model.readTranscript = { transcript }
            model.restoreTranscript = { transcript = $0 }
            model.select(url: URL(string: "https://example.com/a")!, session: session())
            XCTAssertEqual(transcript, "")
            let load = Task { await model.playbackStarted() }
            await service.waitUntilLoading()
            if edited { transcript = "new draft" }
            service.complete()
            await load.value
            XCTAssertEqual(transcript, edited ? "new draft" : "saved transcript")
        }
    }

    private func session(_ email: String = "a@example.com") -> AuthSession {
        AuthSession(email: email, deviceID: "device", accessToken: "access", refreshToken: email, expiresAt: .distantFuture)
    }

    func testLocalFingerprintUsesContentsAndRemoteUsesURL() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.mp3")
        let second = directory.appendingPathComponent("two.mp4")
        try Data("abc".utf8).write(to: first)
        try Data("abc".utf8).write(to: second)
        XCTAssertEqual(try DictationMedia.identify(first).key, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try DictationMedia.identify(first).source, "local")
        XCTAssertEqual(try DictationMedia.identify(first).key, try DictationMedia.identify(second).key)
        XCTAssertEqual(try DictationMedia.identify(first).mediaType, "audio")
        XCTAssertEqual(try DictationMedia.identify(second).mediaType, "video")
        XCTAssertEqual(try DictationMedia.identify(URL(string: "https://example.com/movie.mp4?token=value")!).mediaType, "video")
        XCTAssertEqual(try DictationMedia.identify(URL(string: "https://example.com/track.mp3")!).mediaType, "audio")
        XCTAssertThrowsError(try DictationMedia.identify(directory.appendingPathComponent("missing")))
        XCTAssertEqual(try DictationMedia.identify(URL(string: "https://example.com/a")!).source, "official")
    }

    @MainActor func testLoginPlaybackDirtySnapshotsAndRetry() async {
        let service = Stub()
        let model = DictationPersistence(service: service)
        var text = ""
        var position = 0.0
        model.readText = { text }; model.readPosition = { position }
        model.restore = { text = $0; position = $1 }
        let url = URL(string: "https://example.com/audio")!
        model.select(url: url, session: nil)
        await model.playbackStarted(); await model.tick()
        XCTAssertEqual(service.loads, 0)
        model.select(url: url, session: session())
        await model.tick()
        XCTAssertEqual(service.loads, 0)
        await model.playbackStarted()
        XCTAssertEqual(text, "saved"); XCTAssertEqual(position, 12.345)
        await model.playbackStarted(); await model.tick()
        XCTAssertEqual(service.loads, 1); XCTAssertTrue(service.saves.isEmpty)
        text = "edited"; position = 4.567
        service.failSave = true
        await model.tick()
        service.failSave = false
        await model.tick(); await model.tick()
        XCTAssertEqual(service.saves.count, 2)
        XCTAssertEqual(service.saves.last?.0, "edited")
        XCTAssertEqual(service.saves.last?.1, 4567)
        text = ""
        await model.tick()
        XCTAssertEqual(service.saves.last?.0, "")
        model.select(url: url, session: session("b@example.com"))
        XCTAssertEqual(text, ""); XCTAssertEqual(position, 0)
        await model.tick()
        XCTAssertEqual(service.saves.count, 3)
    }

    @MainActor func testSaveNotificationsBracketRequestsAndReportFailure() async {
        let service = Stub()
        let model = DictationPersistence(service: service)
        var events: [String] = []
        var text = "saved"
        model.readText = { text }
        model.onSaving = { events.append("Saving") }
        model.onSaved = { events.append("Saved") }
        model.onError = { events.append("Error") }
        service.onSave = { events.append("Request") }
        model.select(url: URL(string: "https://example.com/audio")!, session: session())
        await model.tick()
        await model.playbackStarted()
        await model.tick()
        XCTAssertTrue(events.isEmpty, "Skipped saves must not announce saving or success")

        text = "edited"
        service.failSave = true
        await model.tick()
        XCTAssertEqual(events, ["Saving", "Request", "Error"])

        events.removeAll()
        service.failSave = false
        await model.tick()
        XCTAssertEqual(events, ["Saving", "Request", "Saved"])
        await model.tick()
        XCTAssertEqual(events, ["Saving", "Request", "Saved"], "An unchanged snapshot must not send another notification")
    }

    @MainActor func testFailedLoadPreventsSaveAndCanRetry() async {
        let service = Stub(); service.failLoad = true
        let model = DictationPersistence(service: service)
        model.select(url: URL(string: "https://example.com/a")!, session: session())
        model.readText = { "draft" }
        await model.playbackStarted(); await model.tick()
        XCTAssertTrue(service.saves.isEmpty)
        service.failLoad = false
        await model.playbackStarted()
        XCTAssertEqual(service.loads, 2)
    }

    @MainActor func testStaleLoadCannotRestoreAnotherSelection() async {
        let service = DeferredService()
        let model = DictationPersistence(service: service)
        var text = ""
        var transcript = ""
        model.restoreTranscript = { transcript = $0 }
        model.restore = { text = $0; _ = $1 }
        model.select(url: URL(string: "https://example.com/a")!, session: session())
        let load = Task { await model.playbackStarted() }
        await service.waitUntilLoading()
        model.select(url: URL(string: "https://example.com/b")!, session: session("b@example.com"))
        service.complete()
        await load.value
        XCTAssertEqual(text, "")
        XCTAssertEqual(transcript, "")
    }

    func testNotFoundMalformedAndAnonymousResponses() async throws {
        let store = Store(session: session())
        let transport = Transport(status: 404, response: "{}")
        let client = DictationClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: store, transport: transport))
        let media = DictationMedia(source: "official", key: "abc", mediaType: "audio")
        let missing = try await client.load(media: media, session: session())
        XCTAssertNil(missing)
        let malformed = DictationClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: store, transport: Transport(status: 200, response: "{}")))
        do { _ = try await malformed.load(media: media, session: session()); XCTFail("Expected decoding failure") }
        catch is DecodingError { }
        store.data = nil
        do { _ = try await client.load(media: media, session: session()); XCTFail("Expected login required") }
        catch APIClientError.loginRequired { }
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testVideoWireContract() async throws {
        let transport = Transport()
        let client = DictationClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: Store(session: session()), transport: transport))
        let media = try DictationMedia.identify(URL(string: "https://example.com/movie.mp4")!)
        _ = try await client.load(media: media, session: session())
        try await client.save(media: media, session: session(), content: "video notes", position: 0)
        let calls = await transport.calls
        let query = URLComponents(string: try XCTUnwrap(calls[0].0.path))?.queryItems
        XCTAssertEqual(query, [URLQueryItem(name: "source_type", value: media.source), URLQueryItem(name: "media_key", value: media.key)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[1].1) as? [String: Any])
        XCTAssertEqual(object["media_type"] as? String, "video")
    }

    func testWireContractAndAccountBinding() async throws {
        let store = Store(session: session())
        let transport = Transport()
        let client = DictationClient(api: APIClient(baseURL: URL(string: "https://example.com")!, store: store, transport: transport))
        let media = DictationMedia(source: "local", key: "abc", mediaType: "audio")
        let saved = try await client.load(media: media, session: session())
        XCTAssertEqual(saved?.position_ms, 12345)
        try await client.save(media: media, session: session(), content: "hello", position: 456)
        let calls = await transport.calls
        XCTAssertEqual(calls[0].0.path, "/dictations?source_type=local&media_key=abc")
        XCTAssertEqual(calls[0].0.headerFields[.authorization], "Bearer access")
        XCTAssertEqual(calls[1].0.method, .put)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[1].1) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["source_type", "media_key", "media_type", "content", "position_ms"])
        XCTAssertEqual(object["media_type"] as? String, "audio")
        XCTAssertEqual(object["position_ms"] as? Int, 456)
        do {
            try await client.save(media: media, session: session("b@example.com"), content: "wrong user", position: 0)
            XCTFail("Expected session rejection")
        } catch APIClientError.sessionChanged { }
        let count = await transport.calls.count
        XCTAssertEqual(count, 2)
    }
}

private final class Stub: DictationServing {
    var content = "saved"
    var loads = 0
    var saves: [(String, UInt64)] = []
    var failLoad = false
    var failSave = false
    var onSave: () -> Void = {}
    func load(media: DictationMedia, session: AuthSession) async throws -> Dictation? {
        loads += 1
        if failLoad { throw URLError(.notConnectedToInternet) }
        return Dictation(content: content, position_ms: 12345, updated_at: "2026-09-30T15:21:32.123Z")
    }
    func save(media: DictationMedia, session: AuthSession, content: String, position: UInt64) async throws {
        onSave()
        saves.append((content, position))
        if failSave { throw URLError(.notConnectedToInternet) }
    }
}
private final class Store: AuthStoring {
    var data: Data?
    init(session: AuthSession) { data = try! JSONEncoder().encode(AuthRecord(deviceID: "device", session: session)) }
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}
private actor Transport: ClientTransport {
    let status: Int
    let response: String
    init(status: Int = 200, response: String = #"{"content":"saved","position_ms":12345,"updated_at":"2026-09-30T15:21:32.123Z"}"#) {
        self.status = status; self.response = response
    }
    var calls: [(HTTPRequest, Data)] = []
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body { data = try await Data(collecting: body, upTo: .max) } else { data = Data() }
        calls.append((request, data))
        return (HTTPResponse(status: .init(code: status)), HTTPBody(response))
    }
}

@MainActor private final class DeferredService: DictationServing {
    private var pending: CheckedContinuation<Dictation?, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func waitUntilLoading() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func load(media: DictationMedia, session: AuthSession) async throws -> Dictation? {
        await withCheckedContinuation {
            pending = $0
            started?.resume(); started = nil
        }
    }
    func complete() {
        pending?.resume(returning: Dictation(content: "stale", position_ms: 999, updated_at: "now", transcript: "saved transcript"))
        pending = nil
    }
    func save(media: DictationMedia, session: AuthSession, content: String, position: UInt64) async throws { }
}
