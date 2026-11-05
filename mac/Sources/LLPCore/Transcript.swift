import Foundation
import HTTPTypes
import OpenAPIRuntime

public protocol TranscriptServing {
    func save(media: DictationMedia, session: AuthSession, transcript: String) async throws
}

public enum TranscriptError: Error { case tooLong }

public struct TranscriptClient: TranscriptServing {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func save(media: DictationMedia, session: AuthSession, transcript: String) async throws {
        try await save(mediaKey: media.key, session: session, transcript: transcript, media: media)
    }

    public func save(mediaKey: String, session: AuthSession, transcript: String, media: DictationMedia? = nil) async throws {
        guard transcript.utf8.count <= 65535 else { throw TranscriptError.tooLong }
        let key = mediaKey.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
        var request = HTTPRequest(method: .put, scheme: nil, authority: nil, path: "/media-items/\(key)/transcript")
        request.headerFields[.contentType] = "application/json"
        struct Metadata: Encodable { let source_type: String; let media_type: String }
        struct Payload: Encodable { let transcript: String; let media: Metadata? }
        let data = try JSONEncoder().encode(Payload(transcript: transcript, media: media.map { Metadata(source_type: $0.source, media_type: $0.mediaType) }))
        _ = try await api.send(request, body: HTTPBody(data), operationID: "updateTranscript", expectedSession: session)
    }
}

@MainActor public final class TranscriptEditor {
    public var text = ""
    public private(set) var isSaving = false
    public private(set) var isUploading = false
    public private(set) var message = ""
    public var onChange: () -> Void = {}
    private let service: TranscriptServing
    private let ocr: TranscriptOCRServing?
    private var url: URL?
    private var session: AuthSession?
    private var generation = UUID()
    public init(service: TranscriptServing, ocr: TranscriptOCRServing? = nil) { self.service = service; self.ocr = ocr }

    public func select(url: URL?, session: AuthSession?) {
        generation = UUID()
        self.url = url; self.session = session
        text = ""; message = ""; isSaving = false; isUploading = false
        onChange()
    }

    public func upload(url imageURL: URL, contentType: String) async {
        guard !isSaving, !isUploading else { return }
        guard let session, let ocr else {
            DiagnosticLog.event("ocr", stage: "session_or_service_unavailable")
            message = "Log in and configure the server before uploading."; onChange(); return
        }
        let id = generation
        let original = text
        isUploading = true
        message = contentType == "image/heic" || contentType == "image/heif"
            ? "Transforming image…" : "Preparing image…"
        onChange()
        do {
            let prepared = try await Task.detached {
                let file = try FileHandle(forReadingFrom: imageURL)
                defer { try? file.close() }
                let data = try file.read(upToCount: TranscriptOCRImage.sizeLimit) ?? Data()
                return try TranscriptOCRImage.prepare(data, contentType: contentType)
            }.value
            guard id == generation else { return }
            message = "Translating image…"; onChange()
            let recognized = try await ocr.recognize(image: prepared.data, contentType: prepared.contentType, session: session)
            guard id == generation else { return }
            if text == original {
                text = recognized
                message = "Review the recognized text, then Save Transcript."
            } else {
                message = "Draft changed during upload. Kept your edits; upload again to retry."
            }
        } catch {
            DiagnosticLog.failure("ocr", stage: "upload", error: error)
            guard id == generation else { return }
            message = "Could not recognize image. Use an image smaller than 5 MB (including after HEIC conversion) with readable text and retry. Your draft is kept."
            if case APIClientError.http(let response, let data) = error {
                struct BackendError: Decodable { let message: String }
                if let backend = try? JSONDecoder().decode(BackendError.self, from: data),
                   !backend.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    message = "\(backend.message). Your draft is kept."
                } else {
                    message = "Image recognition failed (HTTP \(response.status.code)). Your draft is kept; try again."
                }
            } else if (error as? URLError)?.code == .timedOut {
                message = "Image recognition timed out. Your draft is kept; try again."
            }
        }
        isUploading = false; onChange()
    }

    public func save() async {
        guard !isSaving, !isUploading else { return }
        guard let url else { message = "Select media before saving a transcript."; onChange(); return }
        guard let session else { message = "Log in before saving a transcript."; onChange(); return }
        let snapshot = text
        guard snapshot.utf8.count <= 65535 else {
            message = "Transcript must be at most 65535 UTF-8 bytes."; onChange(); return
        }
        let id = generation
        isSaving = true; message = "Saving transcript…"; onChange()
        do {
            let media = try await Task.detached { try DictationMedia.identify(url) }.value
            guard id == generation else { return }
            try await service.save(media: media, session: session, transcript: snapshot)
            guard id == generation else { return }
            message = text == snapshot ? "Transcript saved." : "Transcript saved. New edits are not saved yet."
        } catch {
            guard id == generation else { return }
            if case APIClientError.http(let response, _) = error, response.status.code == 404 {
                message = "No saved dictation. Play this media, type listening text, wait for autosave, then retry."
            } else {
                message = "Could not save transcript. Your draft is kept; try again."
            }
        }
        isSaving = false; onChange()
    }
}
