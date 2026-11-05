import Foundation
import OSLog
import OpenAPIRuntime

/// Only static operation/stage labels and allowlisted error metadata reach the log.
/// Never serialize errors, requests, responses, URLs, or credential fragments.
public enum DiagnosticLog {
    private static let logger = Logger(subsystem: "LLP", category: "diagnostics")

    static func operation(_ id: String) -> StaticString {
        switch id {
        case "extractTranscript": return "ocr"
        case "login": return "login"
        case "logout": return "logout"
        case "register": return "registration"
        case "refreshAccessToken": return "refresh"
        default: return "api_request"
        }
    }

    public static func event(_ operation: StaticString, stage: StaticString, status: Int? = nil) {
        logger.notice("operation=\(String(describing: operation), privacy: .public) stage=\(String(describing: stage), privacy: .public) status=\(status ?? 0)")
    }

    public static func failure(_ operation: StaticString, stage: StaticString, error: Error) {
        logger.error("operation=\(String(describing: operation), privacy: .public) stage=\(String(describing: stage), privacy: .public) cause=\(safeCause(error), privacy: .public)")
    }

    static func safeCause(_ error: Error) -> String {
        if let client = error as? ClientError { return safeCause(client.underlyingError) }
        if let error = error as? URLError { return "url_error code=\(error.code.rawValue)" }
        if error is CancellationError { return "cancelled" }
        if let error = error as? APIClientError {
            switch error {
            case .loginRequired: return "login_required"
            case .sessionChanged: return "session_changed"
            case .invalidRefreshResponse: return "invalid_refresh_response"
            case .http(let response, _): return "http_status=\(response.status.code)"
            }
        }
        if let error = error as? TranscriptOCRError {
            switch error {
            case .invalidImage: return "invalid_image"
            case .invalidResponse: return "invalid_ocr_response"
            }
        }
        if let error = error as? LoginError { return "login_\(error)" }
        if let error = error as? LogoutError { return "logout_\(error)" }
        if let error = error as? RegistrationError {
            switch error {
            case .invalidInput: return "invalid_input"
            case .duplicateEmail: return "duplicate_email"
            case .emailDeliveryFailed: return "email_delivery_failed"
            case .timeout: return "timeout"
            case .unavailable: return "unavailable"
            }
        }
        if let error = error as? DecodingError {
            switch error {
            case .dataCorrupted: return "decode_data_corrupted"
            case .keyNotFound: return "decode_key_missing"
            case .typeMismatch: return "decode_type_mismatch"
            case .valueNotFound: return "decode_value_missing"
            @unknown default: return "decode_unknown"
            }
        }
        if error is EncodingError { return "encode_failed" }
        if let error = error as? ListeningTextDocumentError {
            switch error {
            case .unsupportedVersion: return "unsupported_document_version"
            case .invalidSpan: return "invalid_span"
            case .spanOutOfBounds: return "span_out_of_bounds"
            case .invalidForegroundColor: return "invalid_color"
            }
        }
        let nsError = error as NSError
        // Domains and userInfo can contain arbitrary application data.
        let domain = [NSCocoaErrorDomain, NSOSStatusErrorDomain, NSPOSIXErrorDomain].contains(nsError.domain)
            ? nsError.domain : "other"
        return "\(domain) code=\(nsError.code)"
    }
}
