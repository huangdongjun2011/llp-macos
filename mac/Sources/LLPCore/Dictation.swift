import Foundation
import CryptoKit
import UniformTypeIdentifiers
import HTTPTypes
import OpenAPIRuntime

public struct Dictation: Codable, Equatable {
    public let content: String
    public let position_ms: UInt64
    public let updated_at: String
    public var transcript: String? = nil
}

public struct DictationMedia: Equatable {
    public let source: String
    public let key: String
    public let mediaType: String

    public static func identify(_ url: URL) throws -> Self {
        do {
            var hash = SHA256()
            if url.isFileURL {
                let file = try FileHandle(forReadingFrom: url)
                defer { do { try file.close() } catch { DiagnosticLog.failure("dictation", stage: "close_file", error: error) } }
                while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
            } else {
                hash.update(data: Data(url.absoluteString.utf8))
            }
            let type = UTType(filenameExtension: url.pathExtension)
            let mediaType = type?.conforms(to: .movie) == true ? "video" : "audio"
            return Self(source: url.isFileURL ? "local" : "official", key: hash.finalize().map { String(format: "%02x", $0) }.joined(), mediaType: mediaType)
        } catch {
            DiagnosticLog.failure("dictation", stage: "identify_media", error: error)
            throw error
        }
    }
}

public protocol DictationServing {
    func load(media: DictationMedia, session: AuthSession) async throws -> Dictation?
    func save(media: DictationMedia, session: AuthSession, content: String, position: UInt64) async throws
}

public struct DictationClient: DictationServing {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func load(media: DictationMedia, session: AuthSession) async throws -> Dictation? {
        do {
            var query = URLComponents()
            query.path = "/dictations"
            query.queryItems = [.init(name: "source_type", value: media.source), .init(name: "media_key", value: media.key)]
            let (_, body) = try await api.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: query.string!), operationID: "loadDictation", expectedSession: session)
            guard let body else { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(Dictation.self, from: await Data(collecting: body, upTo: 16 * 1024 * 1024))
        } catch APIClientError.http(let response, _) where response.status.code == 404 {
            DiagnosticLog.event("dictation", stage: "not_found", status: 404)
            return nil
        } catch {
            DiagnosticLog.failure("dictation", stage: "load", error: error)
            throw error
        }
    }
    public func save(media: DictationMedia, session: AuthSession, content: String, position: UInt64) async throws {
        struct Payload: Encodable { let source_type: String; let media_key: String; let media_type: String; let content: String; let position_ms: UInt64 }
        do {
            var request = HTTPRequest(method: .put, scheme: nil, authority: nil, path: "/dictations")
            request.headerFields[.contentType] = "application/json"
            let data = try JSONEncoder().encode(Payload(source_type: media.source, media_key: media.key, media_type: media.mediaType, content: content, position_ms: position))
            _ = try await api.send(request, body: HTTPBody(data), operationID: "saveDictation", expectedSession: session)
        } catch {
            DiagnosticLog.failure("dictation", stage: "save", error: error)
            throw error
        }
    }
}

/// Main-thread state machine; a failed load never enables an overwrite of unknown server data.
@MainActor public final class DictationPersistence {
    private let service: DictationServing
    private var generation = UUID()
    private var session: AuthSession?
    private var url: URL?
    private var media: DictationMedia?
    private var loaded = false
    private var busy = false
    private var snapshot = ""
    public var readText: () throws -> String = { "" }
    public var readPosition: () -> TimeInterval = { 0 }
    public var restore: (String, TimeInterval) throws -> Void = { _, _ in }
    public var readTranscript: () -> String = { "" }
    public var restoreTranscript: (String) -> Void = { _ in }
    public var onError: () -> Void = {}
    public var onSaving: () -> Void = {}
    public var onSaved: () -> Void = {}
    public init(service: DictationServing) { self.service = service }

    public func select(url: URL?, session: AuthSession?) {
        generation = UUID(); self.url = url; self.session = session
        media = nil; loaded = false; busy = false; snapshot = ""
        do { try restore("", 0) } catch { onError() }
        restoreTranscript("")
    }

    public func playbackStarted() async {
        guard !loaded, !busy, let url, let session else { return }
        busy = true
        let id = generation
        let originalTranscript = readTranscript()
        do {
            let original = try readText()
            let media = try await Task.detached { try DictationMedia.identify(url) }.value
            guard id == generation else { return }
            let saved = try await service.load(media: media, session: session)
            guard id == generation else { return }
            let content = saved?.content ?? ""
            // Validate even when local edits prevent restoration of the saved content.
            _ = try ListeningTextDocument.fromPersistenceContent(content)
            let current = try readText()
            // Preserve edits made while loading, but always restore the saved pointer.
            try restore(current == original ? content : current, Double(saved?.position_ms ?? 0) / 1000)
            // Use the editor's canonical representation for an unchanged loaded snapshot.
            snapshot = current == original ? try readText() : content
            self.media = media; loaded = true; busy = false
            if readTranscript() == originalTranscript {
                restoreTranscript(saved?.transcript ?? "")
            }
        } catch {
            DiagnosticLog.failure("dictation", stage: "restore", error: error)
            guard id == generation else { return }
            busy = false; onError()
        }
    }

    public func tick() async {
        guard loaded, !busy, let media, let session else { return }
        let text: String
        do { text = try readText() } catch {
            DiagnosticLog.failure("dictation", stage: "encode", error: error)
            onError()
            return
        }
        guard text != snapshot else { return }
        let seconds = readPosition()
        let milliseconds = seconds.isFinite ? min(max(seconds * 1000, 0), Double(Int64.max)) : 0
        let id = generation
        busy = true
        onSaving()
        do {
            try await service.save(media: media, session: session, content: text, position: UInt64(milliseconds))
            guard id == generation else { return }
            snapshot = text; busy = false
            onSaved()
        } catch {
            DiagnosticLog.failure("dictation", stage: "autosave", error: error)
            guard id == generation else { return }
            busy = false; onError()
        }
    }
}
