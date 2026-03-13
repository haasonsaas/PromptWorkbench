import AppKit

final class ResponsePanel: NSView {
    let provider: LLMProvider
    let modelCombo = NSComboBox()
    let enabledCheck = NSSwitch()
    private let responseText = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let spinner = NSProgressIndicator()
    private let copyButton: NSButton
    private let innerContainer = NSView()
    private let headerBar = NSView()
    private let metricsBar = NSView()
    private let turnCountLabel = NSTextField(labelWithString: "")
    private var startTime: Date?

    // Multi-turn conversation state
    private(set) var conversationHistory: [ChatMessage] = []
    private var currentAssistantText = ""
    private(set) var lastInputTokens: Int?
    private(set) var lastOutputTokens: Int?
    private(set) var lastDuration: TimeInterval?
    private(set) var lastError: String?

    init(provider: LLMProvider) {
        self.provider = provider
        self.copyButton = NSButton(
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!,
            target: nil, action: nil
        )
        super.init(frame: .zero)
        setupCard()
    }

    required init?(coder: NSCoder) { fatalError() }

    var selectedModel: String {
        let text = modelCombo.stringValue
        return text.isEmpty ? provider.defaultModel : text
    }

    var isEnabled: Bool { enabledCheck.state == .on }

    var currentResponseText: String { responseText.string }

    var turnCount: Int { conversationHistory.filter { $0.role == "user" }.count }

    // MARK: - Multi-turn Conversation API

    func appendUserMessage(_ text: String) {
        let msg = ChatMessage(role: "user", content: text)
        conversationHistory.append(msg)
        renderUserBubble(text)
        updateTurnCount()
    }

    func startAssistantResponse() {
        currentAssistantText = ""
        lastError = nil
        startTime = Date()
        statusLabel.stringValue = "Streaming..."
        statusLabel.textColor = .secondaryLabelColor
        spinner.startAnimation(nil)
        spinner.isHidden = false
        renderAssistantHeader()
    }

    func appendAssistantChunk(_ text: String) {
        currentAssistantText += text
        responseText.textStorage?.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 3; return p }(),
            ]
        ))
        responseText.scrollToEndOfDocument(nil)
    }

    func finishAssistantMessage(inputTokens: Int?, outputTokens: Int?) {
        let msg = ChatMessage(role: "assistant", content: currentAssistantText)
        conversationHistory.append(msg)

        spinner.stopAnimation(nil)
        spinner.isHidden = true
        lastInputTokens = inputTokens
        lastOutputTokens = outputTokens
        lastDuration = startTime.map { Date().timeIntervalSince($0) }
        lastError = nil

        var parts: [String] = []
        if let d = lastDuration { parts.append(String(format: "%.1fs", d)) }
        if let i = inputTokens { parts.append("\(i) in") }
        if let o = outputTokens { parts.append("\(o) out") }
        statusLabel.stringValue = parts.joined(separator: "  ·  ")
        statusLabel.textColor = .secondaryLabelColor

        // Add spacing after response
        responseText.textStorage?.append(NSAttributedString(string: "\n\n"))
        updateTurnCount()
    }

    func showError(_ message: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        lastError = message
        responseText.textStorage?.append(NSAttributedString(
            string: message + "\n\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.systemRed,
            ]
        ))
        statusLabel.stringValue = "Error"
        statusLabel.textColor = .systemRed
        responseText.scrollToEndOfDocument(nil)
    }

    func clearConversation() {
        conversationHistory.removeAll()
        currentAssistantText = ""
        responseText.string = ""
        responseText.textColor = .textColor
        lastInputTokens = nil
        lastOutputTokens = nil
        lastDuration = nil
        lastError = nil
        statusLabel.stringValue = ""
        updateTurnCount()
    }

    /// Build the full API message array including system prompt.
    func buildAPIMessages(systemPrompt: String?) -> [ChatMessage] {
        var msgs: [ChatMessage] = []
        if let sys = systemPrompt, !sys.isEmpty {
            msgs.append(ChatMessage(role: "system", content: sys))
        }
        msgs.append(contentsOf: conversationHistory)
        return msgs
    }

    // MARK: - Rendering

    private func renderUserBubble(_ text: String) {
        let storage = responseText.textStorage!

        // Separator if not first message
        if conversationHistory.count > 1 {
            storage.append(NSAttributedString(
                string: "─────────────────────────────\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: NSColor.separatorColor.withAlphaComponent(0.5),
                ]
            ))
        }

        // "You" header
        storage.append(NSAttributedString(
            string: "You\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: provider.accentColor.withAlphaComponent(0.8),
            ]
        ))

        // User message
        storage.append(NSAttributedString(
            string: text + "\n\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))
        responseText.scrollToEndOfDocument(nil)
    }

    private func renderAssistantHeader() {
        responseText.textStorage?.append(NSAttributedString(
            string: "\(provider.rawValue)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: provider.accentColor,
            ]
        ))
    }

    private func updateTurnCount() {
        let count = turnCount
        turnCountLabel.stringValue = count > 0 ? "\(count) turn\(count == 1 ? "" : "s")" : ""
    }

    // MARK: - Legacy single-turn support

    func reset() {
        clearConversation()
    }

    func appendText(_ text: String) {
        appendAssistantChunk(text)
    }

    func finish(inputTokens: Int?, outputTokens: Int?) {
        finishAssistantMessage(inputTokens: inputTokens, outputTokens: outputTokens)
    }

    // MARK: - Card Layout

    private func setupCard() {
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 10
        layer?.masksToBounds = false

        innerContainer.wantsLayer = true
        innerContainer.layer?.cornerRadius = 12
        innerContainer.layer?.cornerCurve = .continuous
        innerContainer.layer?.masksToBounds = true
        innerContainer.layer?.borderWidth = 0.5
        innerContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        innerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(innerContainer)

        let bg = NSVisualEffectView()
        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(bg)

        setupHeader()
        setupModelPicker()
        setupResponseArea()
        setupMetricsBar()

        NSLayoutConstraint.activate([
            innerContainer.topAnchor.constraint(equalTo: topAnchor),
            innerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            innerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            innerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.topAnchor.constraint(equalTo: innerContainer.topAnchor),
            bg.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor),
            bg.bottomAnchor.constraint(equalTo: innerContainer.bottomAnchor),
        ])
        layoutCard()
    }

    private func setupHeader() {
        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = provider.accentColor.withAlphaComponent(0.10).cgColor
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(headerBar)

        let stripe = NSView()
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = provider.accentColor.cgColor
        stripe.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(stripe)

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: provider.iconSymbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            icon.image = img.withSymbolConfiguration(config)
            icon.contentTintColor = provider.accentColor
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(icon)

        let providerLabel = NSTextField(labelWithString: provider.rawValue)
        providerLabel.font = .systemFont(ofSize: 14, weight: .bold)
        providerLabel.textColor = .labelColor
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(providerLabel)

        turnCountLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        turnCountLabel.textColor = .tertiaryLabelColor
        turnCountLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(turnCountLabel)

        enabledCheck.state = .on
        enabledCheck.controlSize = .mini
        enabledCheck.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(enabledCheck)

        NSLayoutConstraint.activate([
            stripe.topAnchor.constraint(equalTo: innerContainer.topAnchor),
            stripe.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor),
            stripe.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor),
            stripe.heightAnchor.constraint(equalToConstant: 4),
            headerBar.topAnchor.constraint(equalTo: stripe.bottomAnchor),
            headerBar.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 44),
            icon.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            providerLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            providerLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            turnCountLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            turnCountLabel.leadingAnchor.constraint(equalTo: providerLabel.trailingAnchor, constant: 8),
            enabledCheck.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            enabledCheck.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -14),
        ])
    }

    private func setupModelPicker() {
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.addItems(withObjectValues: provider.models)
        modelCombo.stringValue = provider.defaultModel
        modelCombo.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        modelCombo.controlSize = .small
        modelCombo.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(modelCombo)
    }

    private func setupResponseArea() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(scrollView)

        responseText.isEditable = false
        responseText.isSelectable = true
        responseText.drawsBackground = false
        responseText.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        responseText.textColor = .textColor
        responseText.autoresizingMask = [.width]
        responseText.isVerticallyResizable = true
        responseText.textContainerInset = NSSize(width: 10, height: 10)
        responseText.textContainer?.widthTracksTextView = true
        responseText.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = responseText
    }

    private func setupMetricsBar() {
        metricsBar.wantsLayer = true
        metricsBar.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(metricsBar)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        metricsBar.addSubview(sep)

        statusLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        metricsBar.addSubview(statusLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        metricsBar.addSubview(spinner)

        copyButton.bezelStyle = .recessed
        copyButton.isBordered = false
        copyButton.imageScaling = .scaleProportionallyDown
        copyButton.contentTintColor = .tertiaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyResponse)
        copyButton.toolTip = "Copy response"
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        metricsBar.addSubview(copyButton)

        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: metricsBar.topAnchor),
            sep.leadingAnchor.constraint(equalTo: metricsBar.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: metricsBar.trailingAnchor, constant: -12),
            sep.heightAnchor.constraint(equalToConstant: 0.5),
            statusLabel.centerYAnchor.constraint(equalTo: metricsBar.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: metricsBar.leadingAnchor, constant: 14),
            spinner.centerYAnchor.constraint(equalTo: metricsBar.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: metricsBar.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: metricsBar.trailingAnchor, constant: -10),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func layoutCard() {
        NSLayoutConstraint.activate([
            modelCombo.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 10),
            modelCombo.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor, constant: 12),
            modelCombo.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: modelCombo.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: metricsBar.topAnchor),
            metricsBar.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor),
            metricsBar.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor),
            metricsBar.bottomAnchor.constraint(equalTo: innerContainer.bottomAnchor),
            metricsBar.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    override func updateLayer() {
        layer?.shadowColor = NSColor.black.cgColor
        innerContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        headerBar.layer?.backgroundColor = provider.accentColor.withAlphaComponent(0.08).cgColor
    }

    @objc private func copyResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText.string, forType: .string)
        let original = copyButton.contentTintColor
        copyButton.contentTintColor = provider.accentColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.copyButton.contentTintColor = original
        }
    }
}
