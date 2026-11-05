import Foundation
import ImageIO
import UniformTypeIdentifiers
import HTTPTypes
import OpenAPIRuntime

public protocol TranscriptOCRServing {
    func recognize(image: Data, contentType: String, session: AuthSession) async throws -> String
}
public enum TranscriptOCRError: Error { case invalidImage, invalidResponse }

// MB is decimal; both the source file and the encoded upload must be strictly smaller.
public enum TranscriptOCRImage {
    public static let sizeLimit = 5_000_000

    static func prepare(_ data: Data, contentType: String) throws -> (data: Data, contentType: String) {
        guard !data.isEmpty, data.count < sizeLimit else { throw TranscriptOCRError.invalidImage }
        guard contentType == "image/heic" || contentType == "image/heif" else {
            return (data, contentType)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary) else { throw TranscriptOCRError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TranscriptOCRError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0, output.length < sizeLimit else {
            throw TranscriptOCRError.invalidImage
        }
        return (output as Data, "image/jpeg")
    }
}

public struct TranscriptOCRClient: TranscriptOCRServing {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func recognize(image: Data, contentType: String, session: AuthSession) async throws -> String {
        guard !image.isEmpty, image.count < TranscriptOCRImage.sizeLimit else { throw TranscriptOCRError.invalidImage }
        var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/transcripts/ocr")
        request.headerFields[.contentType] = contentType
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let (_, body) = try await api.send(request, body: HTTPBody(image), operationID: "extractTranscript", expectedSession: session)
                guard let body else { throw TranscriptOCRError.invalidResponse }
                struct Response: Decodable { let transcript: String }
                let response = try JSONDecoder().decode(Response.self, from: try await Data(collecting: body, upTo: 1024 * 1024))
                guard !response.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      response.transcript.utf8.count <= 65535 else { throw TranscriptOCRError.invalidResponse }
                return response.transcript
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 35_000_000_000)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
