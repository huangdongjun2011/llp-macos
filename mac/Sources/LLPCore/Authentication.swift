import Foundation
import LLPGenerated
import OpenAPIRuntime
import OpenAPIURLSession
import Security

public struct AuthSession: Codable, Equatable {
    public let email: String
    public let deviceID: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public var authorizationHeader: String? {
        expiresAt > Date() ? "Bearer \(accessToken)" : nil
    }
}

public protocol AuthStoring {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// A single atomic Keychain item keeps device identity and credentials consistent.
public final class KeychainAuthStore: AuthStoring {
    private let service: String
    public init(service: String) { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "authentication"]
    }
    public func read() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            DiagnosticLog.event("keychain", stage: "read_failed", status: Int(status))
            throw LoginError.storage
        }
        return data
    }
    public func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            DiagnosticLog.event("keychain", stage: "write_failed", status: Int(status))
            throw LoginError.storage
        }
    }
}

public enum LoginError: Error, Equatable {
    case invalidInput, unauthorized, timeout, unavailable, storage
    public var message: String {
        switch self {
        case .invalidInput: return "Enter a valid email and a password of 1–72 UTF-8 bytes."
        case .unauthorized: return "Check your email and password and make sure your email is verified."
        case .timeout: return "Sign in timed out. Please try again."
        case .unavailable: return "Sign in is unavailable. Please try again later."
        case .storage: return "Could not access the Keychain. Please unlock it and try again."
        }
    }
}

public protocol LoginServing {
    func login(_ body: Components.Schemas.LoginRequest, completion: @escaping (Result<Components.Schemas.LoginResponse, LoginError>) -> Void) throws -> RegistrationCancelling
}

public final class LoginClient: LoginServing {
    private let client: Client
    public init(baseURL: URL, session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        client = Client(serverURL: baseURL, transport: AuthenticatedTransport(apiClient: APIClient(baseURL: baseURL, transport: URLSessionTransport(configuration: .init(session: session ?? URLSession(configuration: config))))),
                        middlewares: [JSONContentTypeMiddleware()])
    }
    public func login(_ body: Components.Schemas.LoginRequest, completion: @escaping (Result<Components.Schemas.LoginResponse, LoginError>) -> Void) throws -> RegistrationCancelling {
        Task {
            do {
                switch try await client.login(body: .json(body)) {
                case .ok(let response):
                    let tokens = try response.body.json
                    guard !tokens.access_token.isEmpty, !tokens.refresh_token.isEmpty else {
                DiagnosticLog.event("login", stage: "empty_tokens")
                        completion(.failure(.unavailable)); return
                    }
                    DiagnosticLog.event("login", stage: "response_validated")
                    completion(.success(tokens))
                case .badRequest: completion(.failure(.invalidInput))
                case .unauthorized: completion(.failure(.unauthorized))
                default: completion(.failure(.unavailable))
                }
            } catch {
            DiagnosticLog.failure("login", stage: "request_or_decode_response", error: error)
                let underlying = (error as? ClientError)?.underlyingError ?? error
                completion(.failure((underlying as? URLError)?.code == .timedOut ? .timeout : .unavailable))
            }
        }
    }
}

@MainActor public final class LoginModel {
    private typealias Record = AuthRecord
    public private(set) var session: AuthSession?
    public private(set) var isSubmitting = false
    public private(set) var message = ""
    public var onChange: (() -> Void)?
    private let store: AuthStoring
    private let service: LoginServing
    private let logoutService: LogoutServing?
    private var logoutRevoked = false
    private let schedule: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var request: RegistrationCancelling?
    private var deadline: (() -> Void)?
    private var attempt: UUID?

    public init(service: LoginServing,
                store: AuthStoring,
                logoutService: LogoutServing? = nil,
                schedule: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = { delay, action in
                    let work = DispatchWorkItem(block: action)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                    return {
                        work.cancel()
                    }
    }) {
        self.service = service;
        self.store = store;
        self.logoutService = logoutService;
        self.schedule = schedule
        do {
            session = try loadRecord().session
        } catch {
            DiagnosticLog.failure("login", stage: "persist_or_load_session", error: error)
            message = LoginError.storage.message
        }
    }

    private func loadRecord() throws -> Record {
        if let data = try store.read() { return try JSONDecoder().decode(Record.self, from: data) }
        let record = Record(deviceID: UUID().uuidString, session: nil)
        try store.write(JSONEncoder().encode(record))
        return record
    }
    public func submit(email: String, password: String) {
        guard !isSubmitting, session == nil else { DiagnosticLog.event("login", stage: "submission_ignored"); return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !email.contains(where: { $0.isWhitespace }), email.utf8.count <= 255,
              (1...72).contains(password.utf8.count) else {
            DiagnosticLog.event("login", stage: "invalid_input")
            message = LoginError.invalidInput.message; onChange?(); return
        }
        let record: Record
        do { record = try loadRecord() } catch {
            DiagnosticLog.failure("login", stage: "persist_or_load_session", error: error)
            message = LoginError.storage.message; onChange?(); return }
        DiagnosticLog.event("login", stage: "submitting")
        let id = UUID()
        attempt = id; isSubmitting = true; message = ""; onChange?()
        deadline = schedule(5) { [weak self] in self?.finish(id, email: email, deviceID: record.deviceID, result: .failure(.timeout)) }
        do {
            request = try service.login(.init(email: email, password: password, device_id: record.deviceID, platform: "macos")) { [weak self] result in
                DispatchQueue.main.async { self?.finish(id, email: email, deviceID: record.deviceID, result: result) }
            }
        } catch {
            DiagnosticLog.failure("login", stage: "start_request", error: error)
            finish(id, email: email, deviceID: record.deviceID, result: .failure(.unavailable))
        }
    }

    private func finish(_ id: UUID,
                    email: String,
                    deviceID: String,
                    result: Result<Components.Schemas.LoginResponse, LoginError>) {
        guard attempt == id else { DiagnosticLog.event("login", stage: "stale_callback"); return }
        cancel()
        switch result {
        case .failure(let error):
            DiagnosticLog.failure("login", stage: "completion", error: error)
            message = error.message
            onChange?()
            return
        case .success(let tokens):
            guard !tokens.access_token.isEmpty, !tokens.refresh_token.isEmpty else {
                DiagnosticLog.event("login", stage: "empty_tokens")
                message = LoginError.unavailable.message; onChange?();
                return
            }

            let value = AuthSession(email: email,
                                        deviceID: deviceID,
                                        accessToken: tokens.access_token,
                                        refreshToken: tokens.refresh_token,
                                        expiresAt: Date().addingTimeInterval(3600))

            do {
                try store.write(JSONEncoder().encode(Record(deviceID: deviceID, session: value)))
                DiagnosticLog.event("login", stage: "session_persisted")
                session = value
                logoutRevoked = false
                message = ""
            } catch {
            DiagnosticLog.failure("login", stage: "persist_or_load_session", error: error)
                message = LoginError.storage.message
            }
        }
        onChange?()
    }

    public func cancel() {
        if attempt != nil { DiagnosticLog.event("login", stage: "request_state_cleared") }
        attempt = nil; deadline?(); deadline = nil; request?.cancel(); request = nil; isSubmitting = false
    }

    public func signOut() {
        guard !isSubmitting else {
            DiagnosticLog.event("logout", stage: "submission_ignored")
            return
        }

        guard let session else {
            DiagnosticLog.event("logout", stage: "no_session")
            return
        }

        if logoutRevoked {
            clearSession()
            return
        }

        guard let logoutService: any LogoutServing else {
            DiagnosticLog.event("logout", stage: "service_missing")
            message = LogoutError.unavailable.message
            onChange?()
            return
        }

        DiagnosticLog.event("logout", stage: "submitting")
        let id = UUID()
        attempt = id
        isSubmitting = true
        message = ""
        onChange?()
        deadline = schedule(5) { [weak self] in
            self?.finishLogout(id, result: .failure(.timeout))
        }

        do {
            request = try logoutService.logout(deviceID: session.deviceID) { [weak self] result in
                DispatchQueue.main.async {
                    self?.finishLogout(id, result: result)
                }
            }
        } catch {
            DiagnosticLog.failure("logout", stage: "start_request", error: error)
            finishLogout(id, result: .failure(.unavailable))
        }
    }

    private func finishLogout(
        _ id: UUID,
        result: Result<Void, LogoutError>
    ) {
        guard attempt == id else {
            DiagnosticLog.event("logout", stage: "stale_callback")
            return
        }

        cancel()
        switch result {
        case .failure(let error):
            DiagnosticLog.failure("logout", stage: "completion", error: error)
            message = error.message
            onChange?()

        case .success:
            logoutRevoked = true
            clearSession()

        }
    }
    private func clearSession() {
        do {
            var record = try loadRecord()
            record.session = nil
            try store.write(JSONEncoder().encode(record))
            DiagnosticLog.event("logout", stage: "session_cleared")
            session = nil;
            message = "";
            logoutRevoked = false
        } catch {
            DiagnosticLog.failure("logout", stage: "persist_or_load_session", error: error)
            message = LoginError.storage.message }
        onChange?()
    }
}
