import XCTest
import HTTPTypes
@testable import LLPCore

final class DiagnosticLogTests: XCTestCase {
    func testHTTPDiagnosticsExcludeHeadersAndBody() {
        var response = HTTPResponse(status: .unauthorized)
        response.headerFields[.authorization] = "Bearer secret-access-token"
        let error = APIClientError.http(response, Data("secret-refresh-token".utf8))
        XCTAssertEqual(DiagnosticLog.safeCause(error), "http_status=401")
    }

    func testUntrustedErrorTextIsNeverLogged() {
        let secret = "password=secret Authorization=Bearer token api_key=private"
        let error = NSError(domain: secret, code: 42, userInfo: [NSLocalizedDescriptionKey: secret])
        XCTAssertEqual(DiagnosticLog.safeCause(error), "other code=42")
        XCTAssertEqual(DiagnosticLog.safeCause(RegistrationError.invalidInput(secret)), "invalid_input")
        XCTAssertEqual(DiagnosticLog.safeCause(ListeningTextDocumentError.invalidForegroundColor(secret)), "invalid_color")
        XCTAssertEqual(DiagnosticLog.safeCause(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: secret))), "decode_data_corrupted")
    }

    func testTransportDiagnosticsPreserveSafeCause() {
        XCTAssertEqual(DiagnosticLog.safeCause(URLError(.timedOut)), "url_error code=-1001")
        XCTAssertEqual(DiagnosticLog.safeCause(CancellationError()), "cancelled")
        XCTAssertEqual(DiagnosticLog.safeCause(APIClientError.sessionChanged), "session_changed")
    }

    func testOCRDiagnosticsUseSafeLabels() {
        XCTAssertEqual(String(describing: DiagnosticLog.operation("extractTranscript")), "ocr")
        XCTAssertEqual(DiagnosticLog.safeCause(TranscriptOCRError.invalidImage), "invalid_image")
        XCTAssertEqual(DiagnosticLog.safeCause(TranscriptOCRError.invalidResponse), "invalid_ocr_response")
    }

    func testOperationLabelsExcludeArbitraryInput() {
        XCTAssertEqual(String(describing: DiagnosticLog.operation("login")), "login")
        XCTAssertEqual(String(describing: DiagnosticLog.operation("https://secret@example.com?token=secret")), "api_request")
    }
}
