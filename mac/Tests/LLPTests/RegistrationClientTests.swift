import XCTest
@testable import LLPCore

final class RegistrationClientTests: XCTestCase {
    func testHTTPResponsesThroughGeneratedAPIAndURLSession() throws {
        let cases: [(String, Result<Void, RegistrationError>)] = [
            ("success", .success(())), ("duplicate", .failure(.duplicateEmail)),
            ("delivery", .failure(.emailDeliveryFailed)), ("invalid", .failure(.invalidInput("Check your email, password and username."))),
            ("server", .failure(.unavailable)), ("plain", .failure(.unavailable)),
            ("malformed", .failure(.unavailable)), ("timeout", .failure(.timeout)),
            ("offline", .failure(.unavailable))
        ]
        for (scenario, expected) in cases {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RegistrationURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let client = RegistrationClient(baseURL: URL(string: "https://example.com/\(scenario)")!, session: session)
            let completed = expectation(description: scenario)
            let task = try client.register(.init(email: "a@example.com", password: "password")) { result in
                switch (result, expected) {
                case (.success, .success): break
                case (.failure(let actual), .failure(let expected)): XCTAssertEqual(actual, expected)
                default: XCTFail("Unexpected result for \(scenario)")
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
            withExtendedLifetime(task) {}
        }
    }
}

private final class RegistrationURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.lastPathComponent, "register")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let scenario = request.url!.pathComponents[1]
        XCTAssertEqual(request.url?.path, "/\(scenario)/auth/register")
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let requestBody = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(requestBody?["email"], "a@example.com")
        XCTAssertEqual(requestBody?["password"], "password")
        if scenario == "timeout" || scenario == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(scenario == "timeout" ? .timedOut : .notConnectedToInternet))
            return
        }
        let statuses = ["success": 201, "duplicate": 409, "delivery": 503, "invalid": 400, "server": 500, "plain": 404, "malformed": 201]
        let response = HTTPURLResponse(url: request.url!, statusCode: statuses[scenario]!, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = ["plain", "malformed"].contains(scenario) ? "not JSON" : "{\"message\":\"result\"}"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
