import LLPGenerated
import XCTest
@testable import LLPCore

final class RegistrationTests: XCTestCase {
    @MainActor func testValidationUsesPasswordBytesAndDoesNotSendInvalidInput() {
        let service = StubRegistrationService()
        let model = RegistrationModel(service: service)
        for password in ["short", String(repeating: "😀", count: 19)] {
            model.submit(email: "a@example.com", password: password, confirmPassword: password, username: "")
            XCTAssertFalse(model.isSubmitting)
            XCTAssertFalse(model.message.isEmpty)
        }
        model.submit(email: "invalid", password: "password", confirmPassword: "password", username: "")
        model.submit(email: "a@example.com", password: "password", confirmPassword: "password", username: String(repeating: "a", count: 101))
        XCTAssertEqual(service.bodies.count, 0)
    }

    @MainActor func testPasswordConfirmationRejectsMismatchAndAllowsCorrection() {
        let service = StubRegistrationService()
        var deadlinesScheduled = 0
        var changes = 0
        let model = RegistrationModel(service: service, schedule: { _, _ in
            deadlinesScheduled += 1
            return {}
        })
        model.onChange = { changes += 1 }
        for confirmation in ["", "Password", "password "] {
            model.submit(email: "a@example.com", password: "password", confirmPassword: confirmation, username: "")
            XCTAssertFalse(model.isSubmitting)
            XCTAssertFalse(model.didRegister)
            XCTAssertEqual(model.message, "Passwords do not match. Re-enter your password.")
        }
        XCTAssertTrue(service.bodies.isEmpty)
        XCTAssertEqual(deadlinesScheduled, 0)
        XCTAssertEqual(changes, 3)

        model.submit(email: "a@example.com", password: "password", confirmPassword: "password", username: "")
        XCTAssertTrue(model.isSubmitting)
        XCTAssertTrue(model.message.isEmpty)
        XCTAssertEqual(service.bodies.count, 1)
        XCTAssertEqual(service.bodies.first?.password, "password")
        XCTAssertEqual(deadlinesScheduled, 1)
        model.cancel()
    }

    @MainActor func testDeadlineCancelsRequestAndIgnoresLateSuccess() async {
        let service = StubRegistrationService()
        var expire: (() -> Void)?
        let model = RegistrationModel(service: service, schedule: { delay, action in
            XCTAssertEqual(delay, 5)
            expire = action
            return {}
        })
        model.submit(email: " A@Example.com ", password: "password", confirmPassword: "password", username: "")
        XCTAssertTrue(model.isSubmitting)
        XCTAssertEqual(service.bodies.first?.email, "a@example.com")
        model.submit(email: "b@example.com", password: "password", confirmPassword: "password", username: "")
        XCTAssertEqual(service.bodies.count, 1)
        expire?()
        XCTAssertFalse(model.isSubmitting)
        XCTAssertTrue(service.cancelled)
        XCTAssertEqual(model.message, RegistrationError.timeout.message)
        service.completion?(.success(()))
        await drainMainQueue()
        XCTAssertFalse(model.didRegister)
    }

    @MainActor func testSuccessAndFailureReleaseBusyState() async {
        for error in [RegistrationError.duplicateEmail, .emailDeliveryFailed, .unavailable] {
            let service = StubRegistrationService()
            let model = RegistrationModel(service: service)
            model.submit(email: "a@example.com", password: "password", confirmPassword: "password", username: "")
            service.completion?(.failure(error))
            await drainMainQueue()
            XCTAssertFalse(model.isSubmitting)
            XCTAssertEqual(model.message, error.message)
        }
        let service = StubRegistrationService()
        let model = RegistrationModel(service: service)
        model.submit(email: "a@example.com", password: "password", confirmPassword: "password", username: "")
        service.completion?(.success(()))
        await drainMainQueue()
        XCTAssertTrue(model.didRegister)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertTrue(model.message.contains("verify"))
        XCTAssertTrue(model.message.contains("sign in"))
    }

    @MainActor func testCancelIgnoresCompletion() async {
        let service = StubRegistrationService()
        let model = RegistrationModel(service: service)
        model.submit(email: "a@example.com", password: "password", confirmPassword: "password", username: "")
        model.cancel()
        service.completion?(.success(()))
        await drainMainQueue()
        XCTAssertTrue(service.cancelled)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertFalse(model.didRegister)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class StubRegistrationService: RegistrationServing, RegistrationCancelling {
    var bodies: [Components.Schemas.RegisterRequest] = []
    var completion: ((Result<Void, RegistrationError>) -> Void)?
    var cancelled = false
    func register(_ body: Components.Schemas.RegisterRequest, completion: @escaping (Result<Void, RegistrationError>) -> Void) throws -> RegistrationCancelling {
        bodies.append(body)
        self.completion = completion
        return self
    }
    func cancel() { cancelled = true }
}
