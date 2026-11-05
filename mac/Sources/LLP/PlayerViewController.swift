import AppKit
import AVKit
import LLPGenerated
import LLPCore
import UniformTypeIdentifiers

final class PlayerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Layout {
        static let initialContentSize = NSSize(width: 1280, height: 600)
        static let listeningAreaHeight: CGFloat = 480
        static let listeningAreaSpacing: CGFloat = 18
    }

    private let signUpButton = NSButton(title: "Register", target: nil, action: nil)
    private let signInButton = NSButton(title: "Login", target: nil, action: nil)
    private let signOutButton = NSButton(title: "Logout", target: nil, action: nil)
    private let accountLabel = NSTextField(labelWithString: "")
    private var lastAuthenticationMessage = ""
    private var loginSheet: LoginViewController?
    private var loginModel: LoginModel?

    private let playbackController: AudioPlaybackControlling
    private lazy var playlist = AudioPlaylist(playback: playbackController)
    private let audioTable = NSTableView()
    private var playerState = PlayerState()
    private var listeningDraft = ListeningDraft()
    private var progressTimer: Timer?
    private var dictationTimer: Timer?
    private var persistence: DictationPersistence?
    private var persistenceAccount: String?
    private let remoteButton = NSButton(title: "Open URL", target: nil, action: nil)
    private var isScrubbing = false

    private let titleLabel = NSTextField(labelWithString: "No audio file selected")
    private let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let statusLabel = NSTextField(labelWithString: "Open an audio file or folder to begin.")
    private let progressView = SegmentProgressView()
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let speedPopUp = NSPopUpButton()
    private let playPauseButton = NSButton(title: "Play (Command+1)", target: nil, action: nil)
    private let startButton = NSButton(title: "Set Start (Command+2)", target: nil, action: nil)
    private let endButton = NSButton(title: "Set End (Command+3)", target: nil, action: nil)
    private let beforeButton = NSButton(title: "Before (Command+5)", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next (Command+6)", target: nil, action: nil)
    private let replayButton = NSButton(title: "Replay Segment (Command+4)", target: nil, action: nil)
    private let listeningButton = NSButton(title: "Show Listening Area", target: nil, action: nil)
    private let saveTextButton = NSButton(title: "Save Text", target: nil, action: nil)
    private let loadTextButton = NSButton(title: "Load Text", target: nil, action: nil)
    private let markerLabel = NSTextField(labelWithString: "Loop: full track")
    private let listeningScrollView = NSScrollView()
    private let listeningTextView = ListeningTextView()
    private let editors = NSStackView()
    private let transcriptPane = NSStackView()
    private let transcriptTextView = NSTextView()
    private let transcriptToggle = NSButton(checkboxWithTitle: "Transcript", target: nil, action: nil)
    private let transcriptSave = NSButton(title: "Save Transcript", target: nil, action: nil)
    private let transcriptUpload = NSButton(title: "Upload", target: nil, action: nil)
    private let transcriptSpinner = NSProgressIndicator()
    private let transcriptStatus = NSTextField(wrappingLabelWithString: "")
    private var transcriptEditor: TranscriptEditor?
    private let formattingControls = NSStackView()
    private let fontSizePopUp = NSPopUpButton()
    private let textColorPicker = TextColorPicker()
    private let strikethroughButton = NSButton(checkboxWithTitle: "Strikethrough", target: nil, action: nil)

    init(playbackController: AudioPlaybackControlling) {
        self.playbackController = playbackController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        preferredContentSize = Layout.initialContentSize
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureActions()
        refreshAuthentication()
        let configured = ProcessInfo.processInfo.environment["LLP_API_BASE_URL"]
        let url = configured.flatMap(URL.init(string:)) ?? (try! Servers.Server1.url())
        if configured != nil && (URL(string: configured!) == nil || url.host == nil || !["http", "https"].contains(url.scheme ?? "")) {
            DiagnosticLog.event("login", stage: "invalid_configuration")
            signInButton.isEnabled = false
            statusLabel.stringValue = "Set LLP_API_BASE_URL to a valid HTTP or HTTPS server URL."
        } else {
            let store = KeychainAuthStore(service: "LLP.authentication." + url.absoluteString)
            loginModel = LoginModel(service: LoginClient(baseURL: url), store: store, logoutService: LogoutClient(baseURL: url, store: store))
            let transcriptAPI = APIClient(baseURL: url, store: store)
            transcriptEditor = TranscriptEditor(service: TranscriptClient(api: transcriptAPI), ocr: TranscriptOCRClient(api: transcriptAPI))
            transcriptEditor?.onChange = { [weak self] in
                guard let self, let editor = self.transcriptEditor else { return }
                self.transcriptSave.isEnabled = !editor.isSaving && !editor.isUploading
                self.transcriptUpload.isEnabled = !editor.isSaving && !editor.isUploading
                self.transcriptUpload.title = editor.isUploading ? "Uploading…" : "Upload"
                self.transcriptTextView.isEditable = !editor.isUploading
                self.transcriptSpinner.isHidden = !editor.isUploading
                if editor.isUploading { self.transcriptSpinner.startAnimation(nil) }
                else { self.transcriptSpinner.stopAnimation(nil) }
                if self.transcriptTextView.string != editor.text && editor.message == "Review the recognized text, then Save Transcript." {
                    self.transcriptTextView.string = editor.text
                    self.transcriptTextView.undoManager?.removeAllActions()
                }
                self.transcriptStatus.stringValue = editor.message
            }
            persistence = DictationPersistence(service: DictationClient(api: APIClient(baseURL: url, store: store)))
            persistence?.readText = { [weak self] in
                guard let self else { return "" }
                return try ListeningTextDocument(attributedString: self.listeningTextView.attributedString()).persistenceContent()
            }
            persistence?.readPosition = { [weak self] in self?.playbackController.currentTime ?? 0 }
            persistence?.readTranscript = { [weak self] in self?.transcriptTextView.string ?? "" }
            persistence?.restoreTranscript = { [weak self] text in
                guard let self, self.transcriptEditor?.isUploading != true,
                      self.transcriptEditor?.isSaving != true else { return }
                self.transcriptEditor?.text = text
                self.transcriptTextView.string = text
                self.transcriptTextView.undoManager?.removeAllActions()
            }
            persistence?.restore = { [weak self] text, position in
                guard let self else { return }
                let document = try ListeningTextDocument.fromPersistenceContent(text)
                let restored = NSMutableAttributedString(string: document.text, attributes: [
                    .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black
                ])
                let formatted = try document.makeAttributedString()
                formatted.enumerateAttributes(in: NSRange(location: 0, length: formatted.length)) { attributes, range, _ in
                    restored.addAttributes(attributes, range: range)
                }
                self.listeningTextView.textStorage?.setAttributedString(restored)
                self.listeningTextView.undoManager?.removeAllActions()
                self.listeningDraft.text = document.text
                self.playbackController.currentTime = position
                self.updateControls()
            }
            persistence?.onError = { [weak self] in self?.statusLabel.stringValue = "Could not sync listening text. Retry playback to load." }
            persistence?.onSaving = { [weak self] in self?.statusLabel.stringValue = "Saving" }
            persistence?.onSaved = { [weak self] in self?.statusLabel.stringValue = "Saved" }
            dictationTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.persistence?.tick() }
            }
            loginModel?.onChange = { [weak self] in self?.refreshAuthentication() }
            refreshAuthentication()
        }
        playbackController.onFinish = { [weak self] success in
            self?.audioDidFinish(successfully: success)
        }
        updateControls()
        startProgressTimer()
    }

    deinit {
        progressTimer?.invalidate()
        dictationTimer?.invalidate()
    }

    @objc private func showRegistration() {
        guard presentedViewControllers?.isEmpty ?? true else { DiagnosticLog.event("showRegistration", stage: "unavailable_or_cancelled"); return }
        presentAsSheet(RegistrationViewController())
    }

    @objc private func showLogin() {
        guard presentedViewControllers?.isEmpty ?? true,
            let loginModel else {
            return
        }

        let sheet = LoginViewController(model: loginModel)

        let dismissLogin: () -> Void = { [weak self] in
            guard let self,
                let sheet = self.loginSheet else {
                return
            }

            self.loginSheet = nil
            self.dismiss(sheet)

        }
        sheet.onLoginSuccess = dismissLogin
        sheet.onClose = dismissLogin

        loginSheet = sheet

        presentAsSheet(sheet)
    }

    @objc private func signOut() { loginModel?.signOut() }

    private func refreshAuthentication() {
        let session = loginModel?.session
        let account = session.map { $0.email + $0.refreshToken }
        if account != persistenceAccount {
            persistenceAccount = account
            resetPersistence()
        }
        signUpButton.isHidden = session != nil
        signInButton.isHidden = session != nil
        accountLabel.isHidden = session == nil
        signOutButton.isHidden = session == nil
        signOutButton.isEnabled = !(loginModel?.isSubmitting ?? false)
        accountLabel.stringValue = session?.email ?? ""
        loginSheet?.refresh()
        let message = loginModel?.message ?? ""
        if !message.isEmpty {
            statusLabel.stringValue = message
        } else if !lastAuthenticationMessage.isEmpty, statusLabel.stringValue == lastAuthenticationMessage {
            statusLabel.stringValue = ""
        }
        lastAuthenticationMessage = message
    }

    private func buildUI() {
        // Reserve the widest title so state changes do not shift the layout.
        for (button, titles) in [
            (playPauseButton, ["Play (Command+1)", "Pause (Command+1)"]),
            (listeningButton, ["Show Listening Area", "Hide Listening Area"]),
            (transcriptUpload, ["Upload", "Uploading…"])
        ] {
            let originalTitle = button.title
            let width = titles.map { title in
                button.title = title
                return button.intrinsicContentSize.width
            }.max()!
            button.title = originalTitle
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: ceil(width)).isActive = true
        }

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        timeLabel.alignment = .right
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        statusLabel.textColor = .secondaryLabelColor
        markerLabel.textColor = .secondaryLabelColor
        listeningTextView.isEditable = true
        listeningTextView.isSelectable = true
        listeningTextView.isRichText = true
        listeningTextView.allowsUndo = true
        listeningTextView.font = .systemFont(ofSize: 15)
        listeningTextView.textColor = .black
        listeningTextView.backgroundColor = .windowBackgroundColor
        listeningTextView.insertionPointColor = .black
        listeningTextView.string = listeningDraft.text
        listeningTextView.textContainerInset = NSSize(width: 10, height: 10)
        listeningTextView.minSize = NSSize(width: 0, height: 240)
        listeningTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        listeningTextView.isVerticallyResizable = true
        listeningTextView.isHorizontallyResizable = false
        listeningTextView.autoresizingMask = [.width]
        listeningTextView.textContainer?.widthTracksTextView = true

        listeningScrollView.documentView = listeningTextView
        listeningScrollView.hasVerticalScroller = true
        listeningScrollView.drawsBackground = true
        listeningScrollView.backgroundColor = .windowBackgroundColor
        listeningScrollView.borderType = .lineBorder
        listeningScrollView.isHidden = true

        signUpButton.target = self
        signUpButton.action = #selector(showRegistration)
        signInButton.target = self
        signInButton.action = #selector(showLogin)
        signOutButton.target = self
        signOutButton.action = #selector(signOut)
        let accountControls = NSStackView(views: [signUpButton, signInButton, accountLabel, signOutButton])
        accountControls.spacing = 8
        accountControls.translatesAutoresizingMaskIntoConstraints = false
        signUpButton.translatesAutoresizingMaskIntoConstraints = false
        let header = NSStackView(views: [titleLabel, timeLabel])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let controls = NSStackView(views: [openButton, remoteButton, playPauseButton, startButton, endButton, beforeButton, nextButton, replayButton])
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.distribution = .fill

        let speedControls = NSStackView(views: [NSTextField(labelWithString: "Speed:"), speedPopUp])
        speedControls.orientation = .horizontal
        speedControls.spacing = 6
        let listeningControls = NSStackView(views: [listeningButton, speedControls])
        listeningControls.orientation = .vertical
        listeningControls.spacing = 10
        listeningControls.alignment = .leading

        let textFileControls = NSStackView(views: [saveTextButton, loadTextButton])
        textFileControls.orientation = .horizontal
        textFileControls.spacing = 8
        textFileControls.alignment = .centerY

        let fontSizeLabel = NSTextField(labelWithString: "Font size")
        fontSizePopUp.addItems(withTitles: ["12", "14", "15", "16", "18", "20", "24", "28"])
        fontSizePopUp.selectItem(withTitle: "15")
        fontSizePopUp.target = self
        fontSizePopUp.action = #selector(applySelectedFontSize)

        let colorLabel = NSTextField(labelWithString: "Text color")
        textColorPicker.onColorSelected = { [weak self] color in
            self?.applySelectedTextColor(color)
        }

        strikethroughButton.target = self
        strikethroughButton.action = #selector(applySelectedStrikethrough)

        formattingControls.setViews([fontSizeLabel, fontSizePopUp, colorLabel, textColorPicker, strikethroughButton, textFileControls, transcriptToggle], in: .leading)
        formattingControls.orientation = .horizontal
        formattingControls.spacing = 8
        formattingControls.alignment = .centerY
        formattingControls.isHidden = true
        listeningControls.addArrangedSubview(formattingControls)

        transcriptToggle.target = self
        transcriptToggle.action = #selector(toggleTranscript)
        transcriptUpload.target = self
        transcriptUpload.action = #selector(uploadTranscript)
        transcriptSpinner.style = .spinning
        transcriptSpinner.controlSize = .small
        transcriptSpinner.isDisplayedWhenStopped = false
        transcriptSpinner.isHidden = true
        transcriptSave.target = self
        transcriptSave.action = #selector(saveTranscript)
        transcriptTextView.isEditable = true
        transcriptTextView.isSelectable = true
        transcriptTextView.isRichText = false
        transcriptTextView.allowsUndo = true
        transcriptTextView.font = .systemFont(ofSize: 15)
        transcriptTextView.textContainerInset = NSSize(width: 10, height: 10)
        transcriptTextView.minSize = NSSize(width: 0, height: 0)
        transcriptTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        transcriptTextView.isVerticallyResizable = true
        transcriptTextView.isHorizontallyResizable = false
        transcriptTextView.autoresizingMask = [.width]
        transcriptTextView.textContainer?.widthTracksTextView = true
        let transcriptScroll = NSScrollView()
        transcriptScroll.documentView = transcriptTextView
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.borderType = .lineBorder
        transcriptPane.orientation = .vertical
        transcriptPane.alignment = .leading
        transcriptPane.spacing = 8
        let transcriptActions = NSStackView(views: [transcriptUpload, transcriptSpinner, transcriptSave])
        transcriptActions.orientation = .horizontal
        transcriptActions.spacing = 8
        transcriptPane.setViews([NSTextField(labelWithString: "Transcript"), transcriptScroll, transcriptActions, transcriptStatus], in: .leading)
        for child in [transcriptScroll, transcriptStatus] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: transcriptPane.widthAnchor).isActive = true
        }
        editors.orientation = .horizontal
        editors.alignment = .top
        editors.distribution = .fillEqually
        editors.spacing = 12
        editors.setViews([listeningScrollView, transcriptPane], in: .leading)
        listeningScrollView.isHidden = false
        transcriptPane.isHidden = true
        editors.isHidden = true
        for child in [listeningScrollView, transcriptPane] {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.heightAnchor.constraint(equalTo: editors.heightAnchor).isActive = true
        }

        let playerLayout = NSStackView(views: [header, progressView, markerLabel, controls, listeningControls, statusLabel, editors])
        playerLayout.orientation = .vertical
        playerLayout.spacing = Layout.listeningAreaSpacing
        playerLayout.alignment = .leading
        playerLayout.translatesAutoresizingMaskIntoConstraints = false

        for subview in [header, progressView, markerLabel, controls, listeningControls, statusLabel, editors] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                subview.widthAnchor.constraint(equalTo: playerLayout.widthAnchor)
            ])
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("audio"))
        column.title = "Audio files"
        column.width = 240
        audioTable.addTableColumn(column)
        audioTable.dataSource = self
        audioTable.delegate = self
        audioTable.target = self
        audioTable.action = #selector(selectAudio)
        audioTable.allowsEmptySelection = false
        let audioScroll = NSScrollView()
        audioScroll.documentView = audioTable
        audioScroll.hasVerticalScroller = true
        audioScroll.borderType = .bezelBorder
        audioScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(audioScroll)
        if let playback = playbackController as? AVAudioPlaybackController {
            let video = AVPlayerView()
            video.player = playback.player
            video.controlsStyle = .none
            video.translatesAutoresizingMaskIntoConstraints = false
            playerLayout.insertArrangedSubview(video, at: 1)
            video.heightAnchor.constraint(equalToConstant: 160).isActive = true
            video.widthAnchor.constraint(equalTo: playerLayout.widthAnchor).isActive = true
        }
        view.addSubview(playerLayout)
        view.addSubview(accountControls)
        NSLayoutConstraint.activate([
            accountControls.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            accountControls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            playerLayout.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            playerLayout.trailingAnchor.constraint(equalTo: audioScroll.leadingAnchor, constant: -20),
            audioScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            audioScroll.topAnchor.constraint(equalTo: accountControls.bottomAnchor, constant: 12),
            audioScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -28),
            audioScroll.widthAnchor.constraint(equalToConstant: 250),
            playerLayout.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            progressView.heightAnchor.constraint(equalToConstant: progressView.intrinsicContentSize.height),
            editors.heightAnchor.constraint(equalToConstant: Layout.listeningAreaHeight)
        ])
    }

    private func configureActions() {
        speedPopUp.addItems(withTitles: PlaybackSpeed.allCases.map(\.title))
        speedPopUp.selectItem(withTitle: playbackController.playbackSpeed.title)
        speedPopUp.setAccessibilityLabel("Playback speed")
        speedPopUp.target = self
        speedPopUp.action = #selector(changePlaybackSpeed)
        remoteButton.target = self
        remoteButton.action = #selector(openRemoteMedia)
        openButton.target = self
        openButton.action = #selector(openAudioFile)
        playPauseButton.target = self
        playPauseButton.action = #selector(togglePlayPause)
        startButton.target = self
        startButton.action = #selector(setStartMarker)
        endButton.target = self
        endButton.action = #selector(setEndMarker)
        beforeButton.target = self
        beforeButton.action = #selector(moveSegmentBackward)
        nextButton.target = self
        nextButton.action = #selector(moveSegmentForward)
        replayButton.target = self
        replayButton.action = #selector(replaySegment)
        listeningButton.target = self
        listeningButton.action = #selector(toggleListeningArea)
        saveTextButton.target = self
        saveTextButton.action = #selector(saveListeningText)
        loadTextButton.target = self
        loadTextButton.action = #selector(loadListeningText)

        openButton.keyEquivalent = "o"
        playPauseButton.keyEquivalent = "1"
        startButton.keyEquivalent = "2"
        endButton.keyEquivalent = "3"
        replayButton.keyEquivalent = "4"
        nextButton.keyEquivalent = "6"
        beforeButton.keyEquivalent = "5"
        saveTextButton.keyEquivalent = "s"
        loadTextButton.keyEquivalent = "l"

        openButton.keyEquivalentModifierMask = .command
        playPauseButton.keyEquivalentModifierMask = .command
        startButton.keyEquivalentModifierMask = .command
        endButton.keyEquivalentModifierMask = .command
        beforeButton.keyEquivalentModifierMask = .command
        nextButton.keyEquivalentModifierMask = .command
        replayButton.keyEquivalentModifierMask = .command
        saveTextButton.keyEquivalentModifierMask = .command
        loadTextButton.keyEquivalentModifierMask = .command

        progressView.onSeek = { [weak self] time in
            self?.seek(to: time)
        }
        progressView.onMarkerChange = { [weak self] update in
            self?.moveMarker(update)
        }
    }

    @objc private func toggleTranscript() {
        transcriptPane.isHidden = transcriptToggle.state != .on
        if transcriptPane.isHidden {
            view.window?.makeFirstResponder(listeningTextView)
        }
    }

    @objc private func uploadTranscript() {
        guard let editor = transcriptEditor, let window = view.window else {
            DiagnosticLog.event("ocr", stage: "editor_or_window_unavailable")
            transcriptStatus.stringValue = "Configure the server and log in before uploading."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif, .bmp, .tiff, .webP, .heic, .heif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a transcript image (smaller than 5 MB). It will be sent to Google for text recognition."
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size > 0, size < TranscriptOCRImage.sizeLimit else {
                    DiagnosticLog.failure("ocr", stage: "validate_file_size", error: TranscriptOCRError.invalidImage)
                    self.transcriptStatus.stringValue = "Choose a nonempty image smaller than 5 MB. Nothing was uploaded."
                    return
                }
            } catch {
                DiagnosticLog.failure("ocr", stage: "read_file_size", error: error)
                self.transcriptStatus.stringValue = "Could not check the image size. Nothing was uploaded. Choose the image again."
                return
            }
            let types = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff", "webp": "image/webp", "heic": "image/heic", "heif": "image/heif"]
            let contentType = types[url.pathExtension.lowercased()] ?? "application/octet-stream"
            let confirmation = NSAlert()
            confirmation.messageText = "Upload this image?"
            confirmation.informativeText = "\(url.lastPathComponent) will be sent to Google for text recognition. Recognized text will replace your transcript draft."
            confirmation.addButton(withTitle: "Upload")
            confirmation.addButton(withTitle: "Cancel")
            confirmation.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn, let self else { return }
                editor.text = self.transcriptTextView.string
                Task { await editor.upload(url: url, contentType: contentType) }
            }
        }
    }

    @objc private func saveTranscript() {
        guard let editor = transcriptEditor else {
            transcriptStatus.stringValue = "Configure the server and log in before saving."
            return
        }
        editor.text = transcriptTextView.string
        Task { @MainActor [weak self] in
            await editor.save()
            guard let self else { return }
            if editor.message == "Transcript saved.", self.transcriptTextView.string != editor.text {
                self.transcriptStatus.stringValue = "Transcript saved. New edits are not saved yet."
            }
        }
    }

    @objc private func toggleListeningArea() {
        listeningDraft.text = listeningTextView.string
        let isVisible = listeningDraft.toggleEditorVisibility()
        updateListeningAreaVisibility(isVisible)

        if isVisible {
            listeningTextView.window?.makeFirstResponder(listeningTextView)
        }
    }

    private func setListeningAreaVisible(_ isVisible: Bool) {
        guard listeningDraft.isEditorVisible != isVisible else { DiagnosticLog.event("setListeningAreaVisible", stage: "unavailable_or_cancelled"); return }
        listeningDraft.toggleEditorVisibility()
        updateListeningAreaVisibility(isVisible)
    }

    private func updateListeningAreaVisibility(_ isVisible: Bool) {
        editors.isHidden = !isVisible
        formattingControls.isHidden = !isVisible
        listeningButton.title = isVisible ? "Hide Listening Area" : "Show Listening Area"
        resizeWindowForListeningArea(isVisible: isVisible)
    }

    private func resizeWindowForListeningArea(isVisible: Bool) {
        let listeningAreaContentHeight = Layout.listeningAreaHeight + Layout.listeningAreaSpacing
        preferredContentSize = NSSize(
            width: Layout.initialContentSize.width,
            height: Layout.initialContentSize.height + (isVisible ? listeningAreaContentHeight : 0)
        )

        guard let window = view.window else { DiagnosticLog.event("resizeWindowForListeningArea", stage: "unavailable_or_cancelled"); return }

        var frame = window.frame
        let updatedContentHeight = max(
            window.minSize.height,
            window.contentLayoutRect.height + (isVisible ? listeningAreaContentHeight : -listeningAreaContentHeight)
        )
        let updatedFrame = window.frameRect(forContentRect: NSRect(
            x: 0,
            y: 0,
            width: window.contentLayoutRect.width,
            height: updatedContentHeight
        ))

        frame.origin.y -= updatedFrame.height - frame.height
        frame.size.height = updatedFrame.height
        window.setFrame(frame, display: true, animate: true)
    }

    @objc private func applySelectedFontSize() {
        let size = CGFloat(Double(fontSizePopUp.titleOfSelectedItem ?? "") ?? 15)
        applyToSelectionOrTypingAttributes { attributes in
            let currentFont = attributes[.font] as? NSFont ?? listeningTextView.font ?? .systemFont(ofSize: size)
            attributes[.font] = NSFontManager.shared.convert(currentFont, toSize: size)
        }
    }

    private func applySelectedTextColor(_ color: NSColor) {
        applyToSelectionOrTypingAttributes { attributes in
            attributes[.foregroundColor] = color
        }
    }

    @objc private func applySelectedStrikethrough() {
        applyToSelectionOrTypingAttributes { attributes in
            if strikethroughButton.state == .on {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attributes.removeValue(forKey: .strikethroughStyle)
            }
        }
    }

    private func applyToSelectionOrTypingAttributes(_ update: (inout [NSAttributedString.Key: Any]) -> Void) {
        let ranges = listeningTextView.selectedRanges.compactMap { $0.rangeValue }.filter { $0.length > 0 }

        if ranges.isEmpty {
            var typingAttributes = listeningTextView.typingAttributes
            update(&typingAttributes)
            listeningTextView.typingAttributes = typingAttributes
            listeningTextView.window?.makeFirstResponder(listeningTextView)
            return
        }

        guard let textStorage = listeningTextView.textStorage else { DiagnosticLog.event("applyToSelectionOrTypingAttributes", stage: "unavailable_or_cancelled"); return }

        textStorage.beginEditing()
        for range in ranges {
            let boundedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
            guard boundedRange.length > 0 else { continue }

            textStorage.enumerateAttributes(in: boundedRange) { attributes, attributeRange, _ in
                var updatedAttributes = attributes
                update(&updatedAttributes)
                textStorage.setAttributes(updatedAttributes, range: attributeRange)
            }
        }
        textStorage.endEditing()
        listeningTextView.window?.makeFirstResponder(listeningTextView)
    }

    @objc private func saveListeningText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "listening-text.json"

        guard panel.runModal() == .OK, let url = panel.url else { DiagnosticLog.event("saveListeningText", stage: "unavailable_or_cancelled"); return }

        do {
            listeningDraft.text = listeningTextView.string
            let document = ListeningTextDocument(attributedString: listeningTextView.attributedString())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            DiagnosticLog.event("saveListeningText", stage: "completed")
            statusLabel.stringValue = "Saved listening text."
        } catch {
            DiagnosticLog.failure("saveListeningText", stage: "completion", error: error)
            statusLabel.stringValue = "Could not save listening text: \(error.localizedDescription)"
        }
    }

    @objc private func loadListeningText() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { DiagnosticLog.event("loadListeningText", stage: "unavailable_or_cancelled"); return }

        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(ListeningTextDocument.self, from: data)
            let attributedString = try document.makeAttributedString()
            listeningTextView.textStorage?.setAttributedString(attributedString)
            listeningDraft.text = document.text
            setListeningAreaVisible(true)
            listeningTextView.window?.makeFirstResponder(listeningTextView)
            DiagnosticLog.event("loadListeningText", stage: "completed")
            statusLabel.stringValue = "Loaded listening text."
        } catch {
            DiagnosticLog.failure("loadListeningText", stage: "completion", error: error)
            statusLabel.stringValue = "Could not load listening text: \(error.localizedDescription)"
        }
    }

    @objc private func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = audioContentTypes()
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { DiagnosticLog.event("openAudioFile", stage: "unavailable_or_cancelled"); return }
        do {
            try playlist.open(AudioFileDiscovery.files(at: url))
            didLoadPlaylistTrack()
        } catch {
            DiagnosticLog.failure("openAudioFile", stage: "completion", error: error)
            statusLabel.stringValue = "Could not load audio: \(error.localizedDescription)"
        }
        refreshAudioList()
        updateControls()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { playlist.files.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: playlist.files[row].lastPathComponent)
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = playlist.files[row].path
        label.font = .systemFont(ofSize: 13, weight: row == playlist.currentIndex ? .bold : .regular)
        return label
    }

    @objc private func selectAudio() {
        let row = audioTable.clickedRow >= 0 ? audioTable.clickedRow : audioTable.selectedRow
        guard row >= 0 else { DiagnosticLog.event("selectAudio", stage: "unavailable_or_cancelled"); return }
        do {
            try playlist.select(row)
            didLoadPlaylistTrack()
        } catch {
            DiagnosticLog.failure("selectAudio", stage: "completion", error: error)
            statusLabel.stringValue = "Could not load audio: \(error.localizedDescription)"
        }
        refreshAudioList()
        updateControls()
    }

    private func resetPersistence() {
        let url = playlist.currentIndex.map { playlist.files[$0] }
        persistence?.select(url: url, session: loginModel?.session)
        transcriptEditor?.select(url: url, session: loginModel?.session)
        transcriptTextView.string = ""
        transcriptTextView.undoManager?.removeAllActions()
    }

    private func requestDictationLoad() {
        Task { @MainActor [weak self] in await self?.persistence?.playbackStarted() }
    }

    @objc private func openRemoteMedia() {
        let alert = NSAlert()
        alert.messageText = "Open remote audio or video"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        field.placeholderString = "https://example.com/media.mp4"
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = URL(string: field.stringValue), ["https", "http"].contains(url.scheme ?? ""), url.host != nil else {
            DiagnosticLog.event("playback", stage: "invalid_remote_url")
            statusLabel.stringValue = "Enter a valid HTTP or HTTPS media URL."
            return
        }
        do {
            try playlist.open([url])
            didLoadPlaylistTrack()
            refreshAudioList()
        } catch {
            DiagnosticLog.failure("playback", stage: "open_remote", error: error)
            statusLabel.stringValue = "Could not open remote media."
        }
    }

    private func didLoadPlaylistTrack() {
        resetPersistence()
        if playbackController.isPlaying { requestDictationLoad() }
        playerState.loadTrack(duration: playbackController.duration)
        if let index = playlist.currentIndex {
            titleLabel.stringValue = playlist.files[index].lastPathComponent
        }
        DiagnosticLog.event("didLoadPlaylistTrack", stage: "completed")
            statusLabel.stringValue = "Loaded audio file."
        updateControls()
    }

    private func refreshAudioList() {
        audioTable.reloadData()
        if let index = playlist.currentIndex {
            audioTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            audioTable.scrollRowToVisible(index)
        }
    }

    private func audioDidFinish(successfully: Bool) {
        guard successfully else {
            DiagnosticLog.event("playback", stage: "finish_failed")
            statusLabel.stringValue = "Audio playback could not finish."
            updateControls()
            return
        }
        if playerState.isReplayingSegment {
            playbackController.pause()
            playbackController.currentTime = playerState.segment?.end ?? playbackController.duration
            playerState.endSegmentReplay()
            DiagnosticLog.event("audioDidFinish", stage: "completed")
            statusLabel.stringValue = "Segment replay finished."
        } else {
            do {
                if try playlist.advanceAfterFinishing() {
                    didLoadPlaylistTrack()
                    statusLabel.stringValue = "Next audio ready. Press Play to start."
                } else {
                    playbackController.currentTime = 0
                    DiagnosticLog.event("audioDidFinish", stage: "completed")
            statusLabel.stringValue = "Playlist finished."
                }
            } catch {
            DiagnosticLog.failure("audioDidFinish", stage: "completion", error: error)
                statusLabel.stringValue = "Could not load next audio: \(error.localizedDescription)"
            }
        }
        refreshAudioList()
        updateControls()
    }

    @objc private func changePlaybackSpeed() {
        let index = speedPopUp.indexOfSelectedItem
        guard PlaybackSpeed.allCases.indices.contains(index) else {
            DiagnosticLog.event("playback_speed", stage: "invalid_selection")
            updateControls()
            return
        }
        do {
            try playbackController.setPlaybackSpeed(PlaybackSpeed.allCases[index])
            statusLabel.stringValue = "Playback speed: \(playbackController.playbackSpeed.title)"
        } catch {
            DiagnosticLog.failure("playback_speed", stage: "selection", error: error)
            statusLabel.stringValue = "Could not change playback speed. The media may not support this speed or may still be loading."
        }
        updateControls()
    }

    @objc private func togglePlayPause() {
        guard playbackController.duration > 0 else { DiagnosticLog.event("togglePlayPause", stage: "unavailable_or_cancelled"); return }

        if playbackController.isPlaying {
            playbackController.pause()
        } else {
            playbackController.play()
            requestDictationLoad()
        }

        updateControls()
    }

    @objc private func setStartMarker() {
        guard playbackController.duration > 0 else { DiagnosticLog.event("setStartMarker", stage: "unavailable_or_cancelled"); return }
        playerState.apply(.setStart(playbackController.currentTime))
        statusLabel.stringValue = "Start marker set."
        updateControls()
    }

    @objc private func setEndMarker() {
        guard playbackController.duration > 0 else { DiagnosticLog.event("setEndMarker", stage: "unavailable_or_cancelled"); return }
        playerState.apply(.setEnd(playbackController.currentTime))
        statusLabel.stringValue = "End marker set."
        updateControls()
    }

    @objc private func moveSegmentBackward() {
        guard playbackController.duration > 0 else { DiagnosticLog.event("moveSegmentBackward", stage: "unavailable_or_cancelled"); return }

        if playerState.moveSelectedSegmentBackward() {
            playbackController.currentTime = playerState.startMarker ?? playbackController.currentTime
            statusLabel.stringValue = "Moved to previous segment."
        } else if hasExplicitSegment {
            statusLabel.stringValue = "No previous segment available."
        } else {
            statusLabel.stringValue = "Set start and end markers before moving segments."
        }

        updateControls()
    }

    @objc private func moveSegmentForward() {
        guard playbackController.duration > 0 else { DiagnosticLog.event("moveSegmentForward", stage: "unavailable_or_cancelled"); return }

        if playerState.moveSelectedSegmentForward() {
            playbackController.currentTime = playerState.startMarker ?? playbackController.currentTime
            statusLabel.stringValue = "Moved to next segment."
        } else if hasExplicitSegment {
            statusLabel.stringValue = "No next segment available."
        } else {
            statusLabel.stringValue = "Set start and end markers before moving segments."
        }

        updateControls()
    }

    @objc private func replaySegment() {
        guard let segment = playerState.segment else { DiagnosticLog.event("replaySegment", stage: "unavailable_or_cancelled"); return }
        playerState.beginSegmentReplay()
        playbackController.currentTime = segment.start
        playbackController.play()
        requestDictationLoad()
        statusLabel.stringValue = "Replaying selected segment."
        updateControls()
    }

    private func seek(to time: TimeInterval) {
        guard playbackController.duration > 0 else { DiagnosticLog.event("seek", stage: "unavailable_or_cancelled"); return }
        isScrubbing = true
        playbackController.currentTime = time
        playerState.endSegmentReplay()
        isScrubbing = false
        updateControls()
    }

    private func moveMarker(_ update: MarkerUpdate) {
        guard playbackController.duration > 0 else { DiagnosticLog.event("moveMarker", stage: "unavailable_or_cancelled"); return }

        playerState.apply(update)
        statusLabel.stringValue = markerStatusText(for: update)
        updateControls()
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard playbackController.duration > 0 else { return }
        if playerState.duration != playbackController.duration { playerState.loadTrack(duration: playbackController.duration) }

        if playerState.isReplayingSegment, let segment = playerState.segment, segment.shouldRestart(at: playbackController.currentTime) {
            playbackController.pause()
            playbackController.currentTime = segment.end
            playerState.endSegmentReplay()
            DiagnosticLog.event("tick", stage: "completed")
            statusLabel.stringValue = "Segment replay finished."
        }

        if !isScrubbing {
            updateControls()
        }
    }

    private func updateControls() {
        let duration = playbackController.duration
        let currentTime = playbackController.currentTime
        let hasTrack = duration > 0

        speedPopUp.isEnabled = hasTrack
        speedPopUp.selectItem(withTitle: playbackController.playbackSpeed.title)
        progressView.isEnabled = hasTrack
        progressView.duration = duration
        progressView.currentTime = currentTime
        progressView.startMarker = playerState.startMarker
        progressView.endMarker = playerState.endMarker
        progressView.isReplayingSegment = playerState.isReplayingSegment

        playPauseButton.isEnabled = hasTrack
        startButton.isEnabled = hasTrack
        endButton.isEnabled = hasTrack
        beforeButton.isEnabled = hasTrack && hasExplicitSegment
        nextButton.isEnabled = hasTrack && hasExplicitSegment
        replayButton.isEnabled = hasTrack && playerState.segment != nil
        playPauseButton.title = playbackController.isPlaying ? "Pause (Command+1)" : "Play (Command+1)"
        replayButton.title = "Replay Segment (Command+4)"

        timeLabel.stringValue = "\(formatTime(currentTime)) / \(formatTime(duration))"
        markerLabel.stringValue = markerText()
    }

    private var hasExplicitSegment: Bool {
        playerState.startMarker != nil && playerState.endMarker != nil
    }

    private func markerText() -> String {
        let start = playerState.startMarker.map(formatTime) ?? "00:00"
        let end = playerState.endMarker.map(formatTime) ?? formatTime(playbackController.duration)
        return "Loop: \(start) - \(end)"
    }

    private func markerStatusText(for update: MarkerUpdate) -> String {
        switch update {
        case .setStart:
            "Start marker moved."
        case .setEnd:
            "End marker moved."
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let totalSeconds = Int(value.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func audioContentTypes() -> [UTType] {
        [
            UTType(filenameExtension: "mp3"),
            UTType(filenameExtension: "m4a"),
            UTType(filenameExtension: "wav"),
            UTType(filenameExtension: "aiff"),
            .audio, .movie
        ].compactMap { $0 }
    }

}

private final class ListeningTextView: NSTextView {
    private let shortcutResolver = ListeningTextShortcutResolver()

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Validate our custom actions against the same manager that executes them.
        switch menuItem.action {
        case #selector(undo(_:)):
            return undoManager?.canUndo == true
        case #selector(redo(_:)):
            return undoManager?.canRedo == true
        default:
            return super.validateMenuItem(menuItem)
        }
    }

    @objc func undo(_ sender: Any?) {
        guard let undoManager, undoManager.canUndo else { return }
        breakUndoCoalescing()
        undoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        guard let undoManager, undoManager.canRedo else { return }
        breakUndoCoalescing()
        undoManager.redo()
    }

    override func keyDown(with event: NSEvent) {
        let action = shortcutResolver.action(
            for: event.charactersIgnoringModifiers,
            hasOption: event.modifierFlags.contains(.alt),
            hasCommand: event.modifierFlags.contains(.command),
            hasControl: event.modifierFlags.contains(.control),
            hasShift: event.modifierFlags.contains(.shift)
        )

        switch action {
        case .selectAll:
            selectAll(nil)
        case .copy:
            copy(nil)
        case .paste:
            paste(nil)
        case .suppressSystemTextCommand:
            break
        case .passThrough:
            super.keyDown(with: event)
        }
    }
}
