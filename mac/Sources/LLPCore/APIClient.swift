import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

struct AuthRecord: Codable {
    var deviceID: String
    var session: AuthSession?
}

public enum APIClientError: Error {
    case loginRequired
    case invalidRefreshResponse
    case sessionChanged
    case http(HTTPResponse, Data)
}

/// Shared authentication and bounded replay for generated and hand-written APIs.
public actor APIClient {
    public typealias ExpirationDetector = @Sendable (HTTPResponse, Data) -> Bool
    private let baseURL: URL
    private let store: AuthStoring
    private let transport: any ClientTransport
    private let isExpired: ExpirationDetector
    private var refreshTask: Task<AuthSession, Error>?
    private static let publicPaths: Set<String> = [
        "/auth/register", "/auth/login", "/auth/verify", "/auth/resend-verification"
    ]

    public init(baseURL: URL, store: AuthStoring? = nil, transport: (any ClientTransport)? = nil,
                isExpired: @escaping ExpirationDetector = APIClient.accessTokenExpired) {
        self.baseURL = baseURL
        self.store = store ?? KeychainAuthStore(service: "LLP.authentication." + baseURL.absoluteString)
        self.transport = transport ?? URLSessionTransport()
        self.isExpired = isExpired
    }

    /// The contract currently has no protected endpoint error schema. Require an
    /// explicit expiration code, never interpret every 401 as token expiration.
    public nonisolated static func accessTokenExpired(_ response: HTTPResponse, _ data: Data) -> Bool {
        guard response.status.code == 401,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["code"] as? String == "access_token_expired"
    }

    public func send(_ request: HTTPRequest, body: HTTPBody? = nil,
                     operationID: String = "request", expectedSession: AuthSession? = nil) async throws -> (HTTPResponse, HTTPBody?) {
        let operation = DiagnosticLog.operation(operationID)
        var stage: StaticString = "prepare"
        do {
            let path = String((request.path ?? "/").split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
            let anonymous = Self.publicPaths.contains(path) || path == "/auth/refresh"

            // Buffer once so even a single-use request body can be replayed exactly.
            stage = "encode_or_buffer_request"
            let bytes = try await body.mapData()
            var outgoing = request
            outgoing.headerFields[.authorization] = nil
            var current: AuthSession?
            if !anonymous {
                stage = "load_session"
                current = try record()?.session
                guard let current, !current.accessToken.isEmpty else {
                    throw APIClientError.loginRequired }
                if let expectedSession, current.email != expectedSession.email || current.refreshToken != expectedSession.refreshToken {
                    throw APIClientError.sessionChanged
                }
                outgoing.headerFields[.authorization] = "Bearer \(current.accessToken)"
            }
            stage = "transport"
            let first = try await perform(outgoing, bytes: bytes, operationID: operationID)

            if !anonymous, isExpired(first.0, first.1), let current {
                stage = "refresh_session"
                let fresh = try await refresh(current)
                try Task.checkCancellation()
                outgoing.headerFields[.authorization] = "Bearer \(fresh.accessToken)"
                stage = "replay"
                return try checked(await perform(outgoing, bytes: bytes, operationID: operationID))
            }
            stage = "http_response"
            return try checked(first)

        } catch {
            DiagnosticLog.failure(operation, stage: stage, error: error)
            throw error
        }
    }

    private func record() throws -> AuthRecord? {
        try store.read().map { try JSONDecoder().decode(AuthRecord.self, from: $0) }
    }
    private func perform(_ request: HTTPRequest, bytes: Data?, operationID: String) async throws -> (HTTPResponse, Data) {
        try Task.checkCancellation()
        let (response, body) = try await transport.send(request, body: bytes.map { HTTPBody($0) },
                                                       baseURL: baseURL, operationID: operationID)
        DiagnosticLog.event(DiagnosticLog.operation(operationID), stage: "http_response", status: response.status.code)
        return (response, try await body.mapData() ?? Data())
    }
    private func checked(_ result: (HTTPResponse, Data)) throws -> (HTTPResponse, HTTPBody?) {
        guard (200..<300).contains(result.0.status.code) else { throw APIClientError.http(result.0, result.1) }
        DiagnosticLog.event("api_request", stage: "completed")
        return (result.0, HTTPBody(result.1))
    }
    private func refresh(_ original: AuthSession) async throws -> AuthSession {

        guard let saved = try record()?.session else {
            throw APIClientError.loginRequired
        }

        guard saved.deviceID == original.deviceID, saved.refreshToken == original.refreshToken else {
            throw APIClientError.sessionChanged
        }
        if saved.accessToken != original.accessToken {
            return saved
        }

        if let refreshTask {
            DiagnosticLog.event("refresh", stage: "joining_inflight")
            return try await refreshTask.value
        }

        DiagnosticLog.event("refresh", stage: "exchange_started")
        let task = Task { try await self.exchange(original) }

        refreshTask = task
        defer {
            refreshTask = nil
        }
        return try await task.value
    }

    private func exchange(_ original: AuthSession) async throws -> AuthSession {
        var stage: StaticString = "prepare"
        do {
            guard !original.refreshToken.isEmpty else {
                throw APIClientError.loginRequired
            }

            var request = HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/auth/refresh")
            request.headerFields[.contentType] = "application/json"

            stage = "encode_or_buffer_request"
            let bytes = try JSONEncoder().encode(["refresh_token": original.refreshToken])

            stage = "transport"
            let result = try await perform(request, bytes: bytes, operationID: "refreshAccessToken")
            stage = "http_response"
            if result.0.status.code == 401 {
                stage = "load_session_for_revocation"
                if var saved = try record(), saved.session == original {
                    saved.session = nil
                    stage = "persist_revocation"
                    try store.write(JSONEncoder().encode(saved))
                    DiagnosticLog.event("refresh", stage: "session_revoked")
                }
                throw APIClientError.loginRequired
            }
            _ = try checked(result)
            struct Tokens: Decodable { let access_token: String; let token_type: String; let expires_in: Int }
            stage = "decode_response"
            let tokens = try JSONDecoder().decode(Tokens.self, from: result.1)

            stage = "validate_tokens"
            guard !tokens.access_token.isEmpty, tokens.token_type == "Bearer", tokens.expires_in == 3600 else {
                throw APIClientError.invalidRefreshResponse
            }
            stage = "verify_session"
            guard var saved = try record(), saved.session == original else { throw APIClientError.sessionChanged }
            let fresh = AuthSession(email: original.email, deviceID: original.deviceID,
                accessToken: tokens.access_token, refreshToken: original.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(tokens.expires_in)))
            DiagnosticLog.event("refresh", stage: "tokens_validated")
            saved.session = fresh
            stage = "persist_session"
            try store.write(JSONEncoder().encode(saved))
            DiagnosticLog.event("refresh", stage: "completed")
            return fresh

        } catch {
            DiagnosticLog.failure("refresh", stage: stage, error: error)
            throw error
        }
    }
}

private extension Optional where Wrapped == HTTPBody {
    func mapData() async throws -> Data? {
        guard let body = self else { return nil }
        return try await Data(collecting: body, upTo: .max)
    }
}

/// Preserves generated endpoint-specific error decoding after APIClient stops.
struct AuthenticatedTransport: ClientTransport {
    let apiClient: APIClient
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL,
              operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        do { return try await apiClient.send(request, body: body, operationID: operationID) }
        catch APIClientError.http(let response, let data) { return (response, HTTPBody(data)) }
    }
}
