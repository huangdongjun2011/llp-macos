import XCTest
import LLPGenerated
@testable import LLPCore

final class LoginTests: XCTestCase {
    private func tokens() throws -> Components.Schemas.LoginResponse {
        try JSONDecoder().decode(Components.Schemas.LoginResponse.self, from: Data(#"{"access_token":"access","refresh_token":"refresh","token_type":"Bearer","expires_in":3600,"refresh_expires_in":1296000}"#.utf8))
    }
    @MainActor private func drain() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
    @MainActor func testValidationAndDuplicateSubmission() {
        let service = LoginStub()
        let model = LoginModel(service: service, store: MemoryAuthStore())
        for (email, password) in [("invalid", "a"), ("a@example.com", ""), ("a@example.com", String(repeating: "😀", count: 19)), ("a\nb@example.com", "a")] {
            model.submit(email: email, password: password)
        }
        XCTAssertTrue(service.bodies.isEmpty)
        model.submit(email: " A@Example.com ", password: "a")
        model.submit(email: "b@example.com", password: "b")
        XCTAssertEqual(service.bodies.count, 1)
        XCTAssertEqual(service.bodies[0].email, "a@example.com")
        XCTAssertEqual(service.bodies[0].platform, "macos")
        XCTAssertNotNil(UUID(uuidString: service.bodies[0].device_id))
        model.cancel()
    }
    @MainActor func testTimeoutAndCancelledRequestsIgnoreLateSuccess() async throws {
        for cancelled in [false, true] {
            let service = LoginStub()
            var expire: (() -> Void)?
            let model = LoginModel(service: service, store: MemoryAuthStore(), schedule: { delay, action in
                XCTAssertEqual(delay, 5); expire = action; return {}
            })
            model.submit(email: "a@example.com", password: "password")
            if cancelled { model.cancel() } else { expire?() }
            XCTAssertFalse(model.isSubmitting)
            XCTAssertTrue(service.cancelled)
            if !cancelled { XCTAssertEqual(model.message, LoginError.timeout.message) }
            service.completion?(.success(try tokens()))
            await drain()
            XCTAssertNil(model.session)
        }
    }
    @MainActor func testPersistenceRestorationAndSignOutKeepDeviceIdentity() async throws {
        let service = LoginStub()
        let store = MemoryAuthStore()
        let model = LoginModel(service: service, store: store)
        model.submit(email: " A@Example.com ", password: "password")
        let device = service.bodies[0].device_id
        service.completion?(.success(try tokens()))
        await drain()
        XCTAssertFalse(model.isSubmitting)
        XCTAssertEqual(model.session?.authorizationHeader, "Bearer access")
        let logout = LogoutStub()
        let restored = LoginModel(service: service, store: store, logoutService: logout)
        XCTAssertEqual(restored.session, model.session)
        restored.signOut()
        logout.completion?(.success(()))
        await drain()
        XCTAssertNil(restored.session)
        XCTAssertNil(LoginModel(service: service, store: store).session)
        XCTAssertFalse(String(data: store.data!, encoding: .utf8)!.contains("refresh"))
        restored.submit(email: "b@example.com", password: "password")
        XCTAssertEqual(service.bodies.last?.device_id, device)
        restored.cancel()
    }
    @MainActor func testStorageFailureDoesNotPublishSessionOrSendWithoutDevice() async throws {
        let service = LoginStub()
        let store = MemoryAuthStore()
        let model = LoginModel(service: service, store: store)
        model.submit(email: "a@example.com", password: "password")
        store.fail = true
        service.completion?(.success(try tokens()))
        await drain()
        XCTAssertNil(model.session)
        XCTAssertEqual(model.message, LoginError.storage.message)
        model.submit(email: "a@example.com", password: "password")
        XCTAssertEqual(service.bodies.count, 1)
    }
    @MainActor func testErrorsAllowRetryAndOldAttemptCannotCompleteNewAttempt() async throws {
        let service = LoginStub()
        let model = LoginModel(service: service, store: MemoryAuthStore())
        var observedStates: [(submitting: Bool, message: String)] = []
        model.onChange = {
            observedStates.append((model.isSubmitting, model.message))
        }
        defer { model.onChange = nil }
        for error in [LoginError.unauthorized, .invalidInput, .unavailable, .timeout] {
            observedStates.removeAll()
            model.submit(email: "a@example.com", password: "password")
            service.completion?(.failure(error))
            await drain()
            XCTAssertFalse(model.isSubmitting)
            XCTAssertEqual(model.message, error.message)
            XCTAssertEqual(observedStates.map(\.submitting), [true, false])
            XCTAssertEqual(observedStates.map(\.message), ["", error.message])
            XCTAssertNil(model.session)
        }
        XCTAssertEqual(service.bodies.count, 4)
        model.submit(email: "a@example.com", password: "password")
        let old = service.completion
        model.cancel()
        model.submit(email: "b@example.com", password: "password")
        old?(.success(try tokens()))
        await drain()
        XCTAssertTrue(model.isSubmitting)
        XCTAssertNil(model.session)
        model.cancel()
    }
    @MainActor func testDeadlineAndRequestStartFailureNotifyObserversAndAllowRetry() {
        for failsToStart in [false, true] {
            let service = LoginStub()
            service.failsToStart = failsToStart
            var expire: (() -> Void)?
            let model = LoginModel(service: service, store: MemoryAuthStore(), schedule: { _, action in
                expire = action
                return {}
            })
            var observedStates: [(submitting: Bool, message: String)] = []
            model.onChange = {
                observedStates.append((model.isSubmitting, model.message))
            }
            defer { model.onChange = nil }
            model.submit(email: "a@example.com", password: "password")
            if !failsToStart { expire?() }
            let error: LoginError = failsToStart ? .unavailable : .timeout
            XCTAssertEqual(observedStates.map(\.submitting), [true, false])
            XCTAssertEqual(observedStates.map(\.message), ["", error.message])
            XCTAssertNil(model.session)
            service.failsToStart = false
            model.submit(email: "a@example.com", password: "password")
            XCTAssertEqual(service.bodies.count, 2)
            XCTAssertTrue(model.isSubmitting)
            XCTAssertEqual(observedStates.last?.message, "")
            model.cancel()
        }
    }
    @MainActor func testLogoutFailuresTimeoutAndStorageRetry() async throws {
        let service = LoginStub()
        let logout = LogoutStub()
        let store = MemoryAuthStore()
        var expire: (() -> Void)?
        let model = LoginModel(service: service, store: store, logoutService: logout, schedule: { _, action in
            expire = action; return {}
        })
        model.submit(email: "a@example.com", password: "password")
        service.completion?(.success(try tokens()))
        await drain()
        let original = model.session
        let saved = store.data
        for error in [LogoutError.unauthorized, .unavailable, .timeout] {
            model.signOut()
            model.signOut()
            XCTAssertTrue(model.isSubmitting)
            logout.completion?(.failure(error))
            await drain()
            XCTAssertEqual(model.session, original)
            XCTAssertEqual(store.data, saved)
            XCTAssertEqual(model.message, error.message)
            XCTAssertFalse(model.isSubmitting)
        }
        XCTAssertEqual(logout.calls, 3)
        model.signOut()
        let late = logout.completion
        expire?()
        late?(.success(()))
        await drain()
        XCTAssertEqual(model.session, original)
        model.signOut()
        XCTAssertEqual(logout.deviceID, original?.deviceID)
        store.fail = true
        logout.completion?(.success(()))
        await drain()
        XCTAssertEqual(model.message, LoginError.storage.message)
        XCTAssertEqual(model.session, original)
        store.fail = false
        let calls = logout.calls
        model.signOut()
        XCTAssertEqual(logout.calls, calls)
        XCTAssertNil(model.session)
        let record = try JSONDecoder().decode(AuthRecord.self, from: store.data!)
        XCTAssertNil(record.session)
        XCTAssertEqual(record.deviceID, original?.deviceID)
        let json = String(decoding: store.data!, as: UTF8.self)
        for secret in ["access", "refresh", "a@example.com"] { XCTAssertFalse(json.contains(secret)) }
        model.signOut()
        XCTAssertEqual(logout.calls, calls)
    }
    func testExpiredTokenIsNotUsedForAuthorization() {
        let session = AuthSession(email: "a@example.com", deviceID: "device", accessToken: "access", refreshToken: "refresh", expiresAt: .distantPast)
        XCTAssertNil(session.authorizationHeader)
    }
}
private final class MemoryAuthStore: AuthStoring {
    var data: Data?
    var fail = false
    func read() throws -> Data? { if fail { throw LoginError.storage }; return data }
    func write(_ data: Data) throws { if fail { throw LoginError.storage }; self.data = data }
}
private final class LoginStub: LoginServing, RegistrationCancelling {
    var bodies: [Components.Schemas.LoginRequest] = []
    var completion: ((Result<Components.Schemas.LoginResponse, LoginError>) -> Void)?
    var cancelled = false
    var failsToStart = false
    func login(_ body: Components.Schemas.LoginRequest, completion: @escaping (Result<Components.Schemas.LoginResponse, LoginError>) -> Void) throws -> RegistrationCancelling {
        bodies.append(body)
        if failsToStart { throw LoginError.unavailable }
        self.completion = completion
        return self
    }
    func cancel() { cancelled = true }
}

private final class LogoutStub: LogoutServing, RegistrationCancelling {
    var completion: ((Result<Void, LogoutError>) -> Void)?
    var calls = 0
    var deviceID: String?
    func logout(deviceID: String, completion: @escaping (Result<Void, LogoutError>) -> Void) throws -> RegistrationCancelling {
        calls += 1; self.deviceID = deviceID; self.completion = completion; return self
    }
    func cancel() {}
}
