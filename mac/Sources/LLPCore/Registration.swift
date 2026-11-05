import LLPGenerated
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public protocol RegistrationCancelling {
    func cancel()
}
extension Task: RegistrationCancelling where Success == Void, Failure == Never {}

public protocol RegistrationServing {
    func register(_ body: Components.Schemas.RegisterRequest, completion: @escaping (Result<Void, RegistrationError>) -> Void) throws -> RegistrationCancelling
}

public enum RegistrationError: Error, Equatable {
    case invalidInput(String), duplicateEmail, emailDeliveryFailed, timeout, unavailable

    public var message: String {
        switch self {
        case .invalidInput(let message): return message
        case .duplicateEmail: return "This email is already registered. Verify your email, then sign in."
        case .emailDeliveryFailed: return "Your account was saved, but the verification email could not be sent. Request a new verification email; do not register again."
        case .timeout: return "The request timed out. Your account may have been saved. Check your email before trying again."
        case .unavailable: return "Registration is unavailable. Please try again later."
        }
    }
}

public final class RegistrationClient: RegistrationServing {
    private let client: Client

    public init(baseURL: URL = try! Servers.Server1.url(), session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.client = Client(serverURL: baseURL, transport: AuthenticatedTransport(apiClient: APIClient(baseURL: baseURL, transport: URLSessionTransport(
            configuration: .init(session: session ?? URLSession(configuration: configuration))))),
            middlewares: [JSONContentTypeMiddleware()])
    }

    public func register(_ body: Components.Schemas.RegisterRequest, completion: @escaping (Result<Void, RegistrationError>) -> Void) throws -> RegistrationCancelling {
        Task {
            do {
                let response = try await client.register(body: .json(body))
                switch response {
                case .created(let created):
                    _ = try created.body.json
                    DiagnosticLog.event("registration", stage: "response_validated")
                    completion(.success(()))
                case .badRequest: completion(.failure(.invalidInput("Check your email, password and username.")))
                case .conflict: completion(.failure(.duplicateEmail))
                case .serviceUnavailable: completion(.failure(.emailDeliveryFailed))
                default: completion(.failure(.unavailable))
                }
            } catch {
            DiagnosticLog.failure("registration", stage: "request_or_decode_response", error: error)
                // The generated runtime wraps transport errors in ClientError.
                let underlying = (error as? ClientError)?.underlyingError ?? error
                let timedOut = (underlying as? URLError)?.code == .timedOut
                completion(.failure(timedOut ? .timeout : .unavailable))
            }
        }
    }
}

/// Owns the UI deadline independently of URLSession's inactivity timeout.
@MainActor public final class RegistrationModel {
    public private(set) var isSubmitting = false
    public private(set) var didRegister = false
    public private(set) var message = ""
    public var onChange: (() -> Void)?
    private let service: RegistrationServing
    private let schedule: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var request: RegistrationCancelling?
    private var cancelDeadline: (() -> Void)?
    private var attempt: UUID?

    public init(service: RegistrationServing, schedule: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = { delay, action in
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }) {
        self.service = service
        self.schedule = schedule
    }

    public func submit(email: String, password: String, confirmPassword: String, username: String) {
        guard !isSubmitting, !didRegister else { DiagnosticLog.event("registration", stage: "submission_ignored"); return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !email.contains("\r"), !email.contains("\n"), email.utf8.count <= 255 else {
            DiagnosticLog.event("registration", stage: "invalid_email")
            message = "Enter a valid email address."; onChange?(); return
        }
        guard (8...72).contains(password.utf8.count), username.unicodeScalars.count <= 100 else {
            DiagnosticLog.event("registration", stage: "invalid_input")
            message = "Use a password of 8–72 UTF-8 bytes and a username of at most 100 characters."; onChange?(); return
        }
        guard password == confirmPassword else {
            DiagnosticLog.event("registration", stage: "password_mismatch")
            message = "Passwords do not match. Re-enter your password."; onChange?(); return
        }
        DiagnosticLog.event("registration", stage: "submitting")
        let id = UUID()
        attempt = id
        isSubmitting = true
        message = ""
        onChange?()
        cancelDeadline = schedule(5) { [weak self] in
            self?.finish(id, result: .failure(.timeout))
        }
        do {
            request = try service.register(.init(email: email, password: password, username: username)) { [weak self] result in
                DispatchQueue.main.async { self?.finish(id, result: result) }
            }
        } catch {
            DiagnosticLog.failure("registration", stage: "request_or_decode_response", error: error)
            finish(id, result: .failure(.unavailable))
        }
    }

    private func finish(_ id: UUID, result: Result<Void, RegistrationError>) {
        guard attempt == id else { DiagnosticLog.event("registration", stage: "stale_callback"); return }
        cancel()
        switch result {
        case .success:
            DiagnosticLog.event("registration", stage: "completed")
            didRegister = true
            message = "Registration successful. Check your email to verify your identity, then sign in."
        case .failure(let error):
            DiagnosticLog.failure("registration", stage: "completion", error: error)
            message = error.message
        }
        onChange?()
    }

    public func cancel() {
        if attempt != nil { DiagnosticLog.event("registration", stage: "request_state_cleared") }
        attempt = nil
        cancelDeadline?()
        cancelDeadline = nil
        request?.cancel()
        request = nil
        isSubmitting = false
    }
}
