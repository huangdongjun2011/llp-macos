import Foundation
import LLPGenerated
import OpenAPIRuntime
import OpenAPIURLSession

public enum LogoutError: Error, Equatable {
    case unauthorized, timeout, unavailable
    public var message: String {
        switch self {
        case .unauthorized: return "Your session could not be verified. Please try logging out again."
        case .timeout: return "Logout timed out. Please try again."
        case .unavailable: return "Logout is unavailable. Please try again later."
        }
    }
}

public protocol LogoutServing {
    func logout(deviceID: String, completion: @escaping (Result<Void, LogoutError>) -> Void) throws -> RegistrationCancelling
}

public final class LogoutClient: LogoutServing {
    private let client: Client
    public init(baseURL: URL, store: AuthStoring, session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        client = Client(serverURL: baseURL, transport: AuthenticatedTransport(apiClient:
            APIClient(baseURL: baseURL, store: store, transport: URLSessionTransport(configuration:
                .init(session: session ?? URLSession(configuration: config))))),
            middlewares: [JSONContentTypeMiddleware()])
    }
    public func logout(deviceID: String, completion: @escaping (Result<Void, LogoutError>) -> Void) throws -> RegistrationCancelling {
        Task {
            do {
                let result = try await client.logout(body: .json(.init(device_id: deviceID))
            )
            switch result {
                case .ok(let response):
                    _ = try response.body.json
                    DiagnosticLog.event("logout", stage: "response_validated")
                    completion(.success(()))
                case .unauthorized:
                    completion(.failure(.unauthorized))
                default:
                    completion(.failure(.unavailable))
                }
            } catch {
            DiagnosticLog.failure("logout", stage: "request_or_decode_response", error: error)
                let underlying =
                    (error as? ClientError)?.underlyingError ?? error
                let logoutError: LogoutError =
                    (underlying as? URLError)?.code == .timedOut
                        ? .timeout
                        : .unavailable
                completion(.failure(logoutError))
            }
        }
        return TaskCancellation {
            DiagnosticLog.event("logout", stage: "cancellation_requested")
        }
    }
    private final class TaskCancellation: RegistrationCancelling {
    private let onCancel: () -> Void

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}
}
