import XCTest
@testable import LLPCore

final class LoginClientTests: XCTestCase {
    func testHTTPResponsesThroughGeneratedAPIAndURLSession() throws {
        let cases: [(String, LoginError?)] = [
            ("success", nil), ("unauthorized", .unauthorized), ("invalid", .invalidInput),
            ("server", .unavailable), ("plain", .unavailable), ("malformed", .unavailable),
            ("empty", .unavailable), ("timeout", .timeout), ("offline", .unavailable)
        ]
        for (scenario, expected) in cases {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [LoginURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let client = LoginClient(baseURL: URL(string: "https://example.com/\(scenario)")!, session: session)
            let completed = expectation(description: scenario)
            let task = try client.login(.init(email: "a@example.com", password: "password", device_id: "device-1", platform: "macos")) { result in
                switch result {
                case .success(let tokens):
                    XCTAssertNil(expected)
                    XCTAssertEqual(tokens.access_token, "access")
                    XCTAssertEqual(tokens.refresh_token, "refresh")
                case .failure(let error): XCTAssertEqual(error, expected)
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 1)
            withExtendedLifetime(task) {}
        }
    }
}

private final class LoginURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.lastPathComponent, "login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let scenario = request.url!.pathComponents[1]
        XCTAssertEqual(request.url?.path, "/\(scenario)/auth/login")
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
        XCTAssertEqual(requestBody?["device_id"], "device-1")
        XCTAssertEqual(requestBody?["platform"], "macos")
        if scenario == "timeout" || scenario == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(scenario == "timeout" ? .timedOut : .notConnectedToInternet))
            return
        }
        let statuses = ["success": 200, "unauthorized": 401, "invalid": 400, "server": 500, "plain": 404, "malformed": 200, "empty": 200]
        let response = HTTPURLResponse(url: request.url!, statusCode: statuses[scenario]!, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body: String
        if ["plain", "malformed"].contains(scenario) { body = "not JSON" }
        else if ["success", "empty"].contains(scenario) {
            let access = scenario == "empty" ? "" : "access"
            body = "{\"access_token\":\"\(access)\",\"refresh_token\":\"refresh\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"refresh_expires_in\":1296000}"
        } else { body = "{\"message\":\"error\"}" }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
