import LLPGenerated
import AppKit
import LLPCore

final class LoginViewController: NSViewController {
    private let email = NSTextField()
    private let password = NSSecureTextField()
    private let submitButton = NSButton(title: "Sign In", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let model: LoginModel
    public var onLoginSuccess: (() -> Void)?
    var onClose: (() -> Void)?

    init(model: LoginModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        preferredContentSize = NSSize(width: 440, height: 260)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Email"), email],
            [NSTextField(labelWithString: "Password"), password]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        email.setAccessibilityLabel("Email")
        password.setAccessibilityLabel("Password")
        email.placeholderString = "you@example.com"
        password.placeholderString = "1–72 UTF-8 bytes"
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
        let stack = NSStackView(views: [NSTextField(labelWithString: "Sign in to your account"), grid, status, actions])
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
        refresh()

    }

    @objc private func submit() {
        model.submit(email: email.stringValue, password: password.stringValue)
    }

    func refresh() {

        let isEnabled = !model.isSubmitting && model.session == nil

        submitButton.isEnabled = isEnabled

        for field in [email, password] {
            field.isEnabled = isEnabled
        }

        if model.isSubmitting {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }

        status.stringValue = model.message

        if model.session != nil {

            password.stringValue = ""
            onLoginSuccess?()
        }
    }

    @objc private func closeSheet() {
        model.cancel()
        password.stringValue = ""
        onClose?()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        model.cancel()
        password.stringValue = ""
    }
}
