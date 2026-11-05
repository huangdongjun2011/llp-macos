import LLPGenerated
import AppKit
import LLPCore

final class RegistrationViewController: NSViewController {
    private let email = NSTextField()
    private let username = NSTextField()
    private let password = NSSecureTextField()
    private let confirmPassword = NSSecureTextField()
    private let submitButton = NSButton(title: "Sign up", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var model: RegistrationModel?

    override func loadView() {
        view = NSView()
        preferredContentSize = NSSize(width: 440, height: 340)
        let configuredURL = ProcessInfo.processInfo.environment["LLP_API_BASE_URL"]
        let baseURL = configuredURL.flatMap(URL.init(string:)) ?? (try! Servers.Server1.url())
        let validURL = configuredURL == nil || (baseURL.host != nil && ["http", "https"].contains(baseURL.scheme ?? "") && URL(string: configuredURL!) != nil)
        model = RegistrationModel(service: RegistrationClient(baseURL: baseURL))
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Username (optional)"), username],
            [NSTextField(labelWithString: "Email"), email],
            [NSTextField(labelWithString: "Password"), password],
            [NSTextField(labelWithString: "Confirm password"), confirmPassword]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        username.setAccessibilityLabel("Username (optional)")
        email.setAccessibilityLabel("Email")
        password.setAccessibilityLabel("Password")
        confirmPassword.setAccessibilityLabel("Confirm password")
        email.placeholderString = "you@example.com"
        password.placeholderString = "8–72 UTF-8 bytes"
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.keyEquivalent = "\r"
        submitButton.widthAnchor.constraint(equalToConstant: 130).isActive = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        submitButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.trailingAnchor.constraint(equalTo: submitButton.trailingAnchor, constant: -8),
            spinner.centerYAnchor.constraint(equalTo: submitButton.centerYAnchor)
        ])
        let close = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        close.keyEquivalent = "\u{1b}"
        let actions = NSStackView(views: [close, submitButton])
        let stack = NSStackView(views: [NSTextField(labelWithString: "Create your account"), grid, status, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        model?.onChange = { [weak self] in self?.refresh() }
        if !validURL {
            DiagnosticLog.event("registration", stage: "invalid_configuration")
            submitButton.isEnabled = false
            status.stringValue = "Set LLP_API_BASE_URL to a valid HTTP or HTTPS server URL."
        }
    }

    @objc private func submit() {
        model?.submit(email: email.stringValue, password: password.stringValue, confirmPassword: confirmPassword.stringValue, username: username.stringValue)
    }

    private func refresh() {
        guard let model else { return }
        submitButton.isEnabled = !model.isSubmitting && !model.didRegister
        for field in [username, email, password, confirmPassword] { field.isEnabled = !model.isSubmitting && !model.didRegister }
        if model.isSubmitting { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        status.stringValue = model.message
        if model.didRegister {
            password.stringValue = ""
            confirmPassword.stringValue = ""
        }
    }

    @objc private func closeSheet() {
        model?.cancel()
        password.stringValue = ""
        confirmPassword.stringValue = ""
        dismiss(self)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        model?.cancel()
        password.stringValue = ""
        confirmPassword.stringValue = ""
    }
}
