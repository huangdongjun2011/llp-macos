import XCTest
import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import LLPCore

final class APIClientTests: XCTestCase {
    private let baseURL = URL(string: "https://example.com/api")!

    func testExpiredAccessRefreshesPersistsAndReplaysBody() async throws {
        let store = MemoryStore()
        let transport = ScriptTransport([
            (401, #"{"code":"access_token_expired"}"#),
            (200, #"{"access_token":"new","token_type":"Bearer","expires_in":3600}"#),
            (200, "done")
        ])
        let client = APIClient(baseURL: baseURL, store: store, transport: transport)
        let response = try await client.send(HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/resource?x=1"), body: HTTPBody("payload"))
        XCTAssertEqual(response.0.status.code, 200)
        let calls = await transport.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[0].0.headerFields[.authorization], "Bearer old")
        XCTAssertEqual(calls[1].0.path, "/auth/refresh")
        XCTAssertEqual(calls[1].0.method, .post)
        XCTAssertNil(calls[1].0.headerFields[.authorization])
        XCTAssertEqual(calls[1].0.headerFields[.contentType], "application/json")
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: calls[1].1), ["refresh_token": "refresh"])
        XCTAssertEqual(calls[2].0.headerFields[.authorization], "Bearer new")
        XCTAssertEqual(calls[2].0.path, calls[0].0.path)
        XCTAssertEqual(calls[2].1, calls[0].1)
        let saved = try JSONDecoder().decode(AuthRecord.self, from: store.data!)
        XCTAssertEqual(saved.session?.accessToken, "new")
        XCTAssertEqual(saved.session?.refreshToken, "refresh")
        XCTAssertEqual(saved.deviceID, "device")
    }

    func testPublicWhitelistDoesNotReadKeychainOrSendAuthorization() async throws {
        for path in ["register", "login", "verify", "resend-verification"] {
            let store = MemoryStore(); store.failRead = true
            let transport = ScriptTransport([(200, "{}")])
            let client = APIClient(baseURL: baseURL, store: store, transport: transport)
            var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/auth/\(path)?token=value")
            request.headerFields[.authorization] = "Bearer accidental"
            _ = try await client.send(request)
            let calls = await transport.calls
            XCTAssertNil(calls[0].0.headerFields[.authorization])
        }
    }

    func testOtherErrorsStopWithoutRefresh() async throws {
        for status in [400, 401, 403, 404, 500] {
            let transport = ScriptTransport([(status, #"{"code":"invalid_token"}"#)])
            let client = APIClient(baseURL: baseURL, store: MemoryStore(), transport: transport)
            do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected error") }
            catch APIClientError.http(let response, _) { XCTAssertEqual(response.status.code, status) }
            let count = await transport.calls.count
            XCTAssertEqual(count, 1)
        }
    }

    func testRetryIsBounded() async throws {
        let expired = (401, #"{"code":"access_token_expired"}"#)
        let transport = ScriptTransport([expired, (200, #"{"access_token":"new","token_type":"Bearer","expires_in":3600}"#), expired])
        let client = APIClient(baseURL: baseURL, store: MemoryStore(), transport: transport)
        do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected error") }
        catch APIClientError.http(let response, _) { XCTAssertEqual(response.status.code, 401) }
        let count = await transport.calls.count
        XCTAssertEqual(count, 3)
    }

    func testRejectedRefreshRequiresLoginAndClearsSession() async throws {
        let store = MemoryStore()
        let transport = ScriptTransport([(401, #"{"code":"access_token_expired"}"#), (401, "{}")])
        let client = APIClient(baseURL: baseURL, store: store, transport: transport)
        do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected login") }
        catch APIClientError.loginRequired {}
        let saved = try JSONDecoder().decode(AuthRecord.self, from: store.data!)
        XCTAssertNil(saved.session)
        XCTAssertEqual(saved.deviceID, "device")
    }

    func testInvalidRefreshAndStorageFailurePreventReplay() async throws {
        for body in ["not JSON", #"{"access_token":"","token_type":"Bearer","expires_in":3600}"#,
                     #"{"access_token":"new","token_type":"Bearer","expires_in":3600}"#] {
            let store = MemoryStore(); store.failWrite = true
            let original = store.data
            let transport = ScriptTransport([(401, #"{"code":"access_token_expired"}"#), (200, body)])
            let client = APIClient(baseURL: baseURL, store: store, transport: transport)
            do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected failure") }
            catch {}
            XCTAssertEqual(store.data, original)
            let count = await transport.calls.count
            XCTAssertEqual(count, 2)
        }
    }

    func testNetworkFailurePropagatesWithoutRetry() async throws {
        let transport = ScriptTransport([])
        let client = APIClient(baseURL: baseURL, store: MemoryStore(), transport: transport)
        do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected failure") }
        catch let error as URLError { XCTAssertEqual(error.code, .badServerResponse) }
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testRefreshServerErrorPreservesSessionAndStops() async throws {
        let store = MemoryStore()
        let original = store.data
        let transport = ScriptTransport([(401, #"{"code":"access_token_expired"}"#), (503, "{}")])
        let client = APIClient(baseURL: baseURL, store: store, transport: transport)
        do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/resource")); XCTFail("Expected failure") }
        catch APIClientError.http(let response, _) { XCTAssertEqual(response.status.code, 503) }
        XCTAssertEqual(store.data, original)
        let count = await transport.calls.count
        XCTAssertEqual(count, 2)
    }

    func testMissingSessionAndLookalikeWhitelistRequireLogin() async throws {
        let store = MemoryStore(); store.data = nil
        let transport = ScriptTransport([])
        let client = APIClient(baseURL: baseURL, store: store, transport: transport)
        do { _ = try await client.send(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/private/auth/login")); XCTFail("Expected login") }
        catch APIClientError.loginRequired {}
        let count = await transport.calls.count
        XCTAssertEqual(count, 0)
    }
}

private final class MemoryStore: AuthStoring {
    var data: Data? = Data(#"{"deviceID":"device","session":{"email":"a@example.com","deviceID":"device","accessToken":"old","refreshToken":"refresh","expiresAt":0}}"#.utf8)
    var failRead = false
    var failWrite = false
    func read() throws -> Data? { if failRead { throw LoginError.storage }; return data }
    func write(_ data: Data) throws { if failWrite { throw LoginError.storage }; self.data = data }
}

private actor ScriptTransport: ClientTransport {
    var responses: [(Int, String)]
    var calls: [(HTTPRequest, Data)] = []
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body { data = try await Data(collecting: body, upTo: .max) } else { data = Data() }
        calls.append((request, data))
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let response = responses.removeFirst()
        return (HTTPResponse(status: .init(code: response.0)), HTTPBody(response.1))
    }
}
