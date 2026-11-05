import XCTest
@testable import LLPCore

final class LogoutClientTests: XCTestCase {
    func testGeneratedLogoutRequestAndResponses() throws {
        let cases: [(String, LogoutError?)] = [("success", nil), ("unauthorized", LogoutError.unauthorized),
            ("invalid", .unavailable), ("media", .unavailable), ("server", .unavailable),
            ("malformed", .unavailable), ("timeout", .timeout), ("offline", .unavailable)]
        for (scenario, expected) in cases {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [LogoutURLProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let store = LogoutStore()
            let client = LogoutClient(baseURL: URL(string: "https://example.com/\(scenario)")!, store: store, session: session)
            let done = expectation(description: scenario)
            let task = try client.logout(deviceID: "device-1") { result in
                switch result {
                case .success: XCTAssertNil(expected)
                case .failure(let error): XCTAssertEqual(error, expected)
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
            withExtendedLifetime(task) {}
        }
    }
}
private final class LogoutStore: AuthStoring {
    func read() throws -> Data? {
        try JSONEncoder().encode(AuthRecord(deviceID: "device-1", session: AuthSession(
            email: "a@example.com", deviceID: "device-1", accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)))
    }
    func write(_ data: Data) throws { XCTFail("Logout transport must not erase credentials before model handles success") }
}
private final class LogoutURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let scenario = request.url!.pathComponents[1]
        XCTAssertEqual(request.url?.path, "/\(scenario)/auth/logout")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
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
        let body = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(body, ["device_id": "device-1"])
        if scenario == "timeout" || scenario == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(scenario == "timeout" ? .timedOut : .notConnectedToInternet))
            return
        }
        let statuses = ["success": 200, "unauthorized": 401, "invalid": 400, "media": 415, "server": 500, "malformed": 200]
        let response = HTTPURLResponse(url: request.url!, statusCode: statuses[scenario]!, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((scenario == "malformed" ? "bad JSON" : "{\"message\":\"result\"}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
