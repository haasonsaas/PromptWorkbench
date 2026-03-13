import AppKit

private extension NSToolbarItem.Identifier {
    static let sendAll = NSToolbarItem.Identifier("SendAll")
    static let newConversation = NSToolbarItem.Identifier("NewConversation")
    static let temperature = NSToolbarItem.Identifier("Temperature")
    static let history = NSToolbarItem.Identifier("History")
    static let export = NSToolbarItem.Identifier("Export")
    static let settings = NSToolbarItem.Identifier("Settings")
}

final class MainWindowController: NSWindowController, NSToolbarDelegate, NSSplitViewDelegate, HistoryPanelDelegate {
    private let systemPromptView = NSTextView()
    private let userPromptView = NSTextView()
    private let tempField = NSTextField(string: "0.7")
    private var panels: [ResponsePanel] = []
    private var activeTasks: [Task<Void, Never>] = []
    private var sendButton: NSButton!
    private var isSending = false
    private var splitView: NSSplitView!
    private var historyPopover: NSPopover?
    private var historyController: HistoryPanelController?

    private let sysPlaceholder = NSTextField(labelWithString: "Optional system instructions...")
    private let userPlaceholder = NSTextField(labelWithString: "Type a message...  ⌘↩ to send")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1300, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Prompt Workbench"
        window.subtitle = "Compare LLM responses side-by-side"
        window.minSize = NSSize(width: 960, height: 600)
        window.center()
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        self.init(window: window)

        setupToolbar()
        setupUI()

        if let savedSys = UserDefaults.standard.string(forKey: "defaultSystemPrompt"), !savedSys.isEmpty {
            systemPromptView.string = savedSys
            sysPlaceholder.isHidden = true
        }
        if let savedTemp = UserDefaults.standard.string(forKey: "defaultTemperature"), !savedTemp.isEmpty {
            tempField.stringValue = savedTemp
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let splitView = self.splitView else { return }
            let height = splitView.bounds.height
            if height > 0 { splitView.setPosition(height * 0.30, ofDividerAt: 0) }
        }

        registerCommands()
        setupCommandKShortcut()
    }

    // MARK: - Command Palette

    private func registerCommands() {
        let cmds: [Command] = [
            Command(name: "Send All", icon: "paperplane.fill", shortcut: "⌘↩", section: "Actions") { [weak self] in
                self?.sendAll()
            },
            Command(name: "New Conversation", icon: "plus.message", shortcut: "⌘N", section: "Actions") { [weak self] in
                self?.newConversation()
            },
            Command(name: "Stop Streaming", icon: "stop.fill", shortcut: "", section: "Actions") { [weak self] in
                self?.stopAll()
            },
            Command(name: "Settings", icon: "gearshape", shortcut: "⌘,", section: "Actions") {
                (NSApp.delegate as? AppDelegate)?.openSettings()
            },
            Command(name: "Copy as Markdown", icon: "doc.richtext", shortcut: "⌘⇧C", section: "Export") { [weak self] in
                self?.copyAsMarkdown()
            },
            Command(name: "Copy as JSON", icon: "curlybraces", shortcut: "⌘⇧J", section: "Export") { [weak self] in
                self?.copyAsJSON()
            },
            Command(name: "Save as Markdown...", icon: "square.and.arrow.down", shortcut: "⌘⇧E", section: "Export") { [weak self] in
                self?.saveAsMarkdown()
            },
            Command(name: "Save as JSON...", icon: "square.and.arrow.down", shortcut: "", section: "Export") { [weak self] in
                self?.saveAsJSON()
            },
            Command(name: "Toggle Anthropic", icon: "brain.head.profile.fill", shortcut: "", section: "Providers") { [weak self] in
                self?.toggleProvider(.anthropic)
            },
            Command(name: "Toggle OpenAI", icon: "sparkles", shortcut: "", section: "Providers") { [weak self] in
                self?.toggleProvider(.openAI)
            },
            Command(name: "Toggle OpenRouter", icon: "arrow.triangle.branch", shortcut: "", section: "Providers") { [weak self] in
                self?.toggleProvider(.openRouter)
            },
            Command(name: "Focus System Prompt", icon: "text.alignleft", shortcut: "", section: "Navigation") { [weak self] in
                self?.window?.makeFirstResponder(self?.systemPromptView)
            },
            Command(name: "Focus Message Input", icon: "character.cursor.ibeam", shortcut: "", section: "Navigation") { [weak self] in
                self?.window?.makeFirstResponder(self?.userPromptView)
            },
            Command(name: "Toggle Full Screen", icon: "arrow.up.left.and.arrow.down.right", shortcut: "⌘F", section: "Window") { [weak self] in
                self?.window?.toggleFullScreen(nil)
            },
        ]
        CommandPaletteController.shared.register(cmds)
    }

    private func setupCommandKShortcut() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "k" {
                self?.toggleCommandPalette()
                return nil
            }
            return event
        }
    }

    @objc private func toggleCommandPalette() {
        CommandPaletteController.shared.toggle(relativeTo: window)
    }

    private func toggleProvider(_ provider: LLMProvider) {
        guard let panel = panels.first(where: { $0.provider == provider }) else { return }
        panel.enabledCheck.state = panel.enabledCheck.state == .on ? .off : .on
    }

    // MARK: - Split View Delegate

    func splitView(_ sv: NSSplitView, constrainMinCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { 140 }
    func splitView(_ sv: NSSplitView, constrainMaxCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { sv.bounds.height * 0.55 }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sendAll, .newConversation, .flexibleSpace, .temperature, .space, .history, .export, .settings]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sendAll, .newConversation, .temperature, .history, .export, .settings, .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .sendAll:
            let item = NSToolbarItem(itemIdentifier: .sendAll)
            let btn = NSButton(title: " Send All ", target: self, action: #selector(sendAll))
            btn.bezelStyle = .rounded
            btn.bezelColor = NSColor.controlAccentColor
            btn.keyEquivalent = "\r"
            btn.keyEquivalentModifierMask = .command
            btn.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send")
            btn.imagePosition = .imageLeading
            btn.font = .systemFont(ofSize: 13, weight: .semibold)
            sendButton = btn
            item.view = btn
            item.label = "Send"
            item.toolTip = "Send to all enabled providers (⌘↩)"
            return item

        case .newConversation:
            let item = NSToolbarItem(itemIdentifier: .newConversation)
            let btn = NSButton(
                image: NSImage(systemSymbolName: "plus.message", accessibilityDescription: "New")!,
                target: self, action: #selector(newConversation)
            )
            btn.bezelStyle = .toolbar
            item.view = btn
            item.label = "New Chat"
            item.toolTip = "Clear all conversations (⌘N)"
            return item

        case .temperature:
            let item = NSToolbarItem(itemIdentifier: .temperature)
            let label = NSTextField(labelWithString: "Temp")
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            tempField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tempField.alignment = .center
            tempField.frame = NSRect(x: 0, y: 0, width: 48, height: 22)
            let stack = NSStackView(views: [label, tempField])
            stack.spacing = 4
            item.view = stack
            item.label = "Temperature"
            return item

        case .history:
            let item = NSToolbarItem(itemIdentifier: .history)
            let btn = NSButton(
                image: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History")!,
                target: self, action: #selector(toggleHistory(_:))
            )
            btn.bezelStyle = .toolbar
            item.view = btn
            item.label = "History"
            item.toolTip = "Browse prompt history (⌘Y)"
            return item

        case .export:
            let item = NSToolbarItem(itemIdentifier: .export)
            let btn = NSButton(
                image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export")!,
                target: self, action: #selector(showExportMenu(_:))
            )
            btn.bezelStyle = .toolbar
            item.view = btn
            item.label = "Export"
            item.toolTip = "Export comparison"
            return item

        case .settings:
            let item = NSToolbarItem(itemIdentifier: .settings)
            let btn = NSButton(
                image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
                target: nil, action: #selector(AppDelegate.openSettings)
            )
            btn.bezelStyle = .toolbar
            item.view = btn
            item.label = "Settings"
            return item

        default:
            return nil
        }
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 4),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        let promptArea = buildPromptArea()
        let responseArea = buildResponseArea()
        splitView.addArrangedSubview(promptArea)
        splitView.addArrangedSubview(responseArea)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
    }

    private func buildPromptArea() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let sysLabel = sectionLabel("SYSTEM")
        let sysScroll = makePromptEditor(systemPromptView, placeholder: sysPlaceholder)
        let userLabel = sectionLabel("MESSAGE")
        let userScroll = makePromptEditor(userPromptView, placeholder: userPlaceholder)

        for v in [sysLabel, sysScroll, userLabel, userScroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        NSLayoutConstraint.activate([
            sysLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            sysLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            sysScroll.topAnchor.constraint(equalTo: sysLabel.bottomAnchor, constant: 5),
            sysScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sysScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            userLabel.topAnchor.constraint(equalTo: sysScroll.bottomAnchor, constant: 12),
            userLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            userScroll.topAnchor.constraint(equalTo: userLabel.bottomAnchor, constant: 5),
            userScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            userScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            userScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            sysScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            userScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            userScroll.heightAnchor.constraint(equalTo: sysScroll.heightAnchor, multiplier: 2.0),
        ])
        return container
    }

    private func buildResponseArea() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        panels = LLMProvider.allCases.map { ResponsePanel(provider: $0) }
        let stack = NSStackView(views: panels)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.5 as CGFloat,
            ]
        )
        return label
    }

    private func makePromptEditor(_ textView: NSTextView, placeholder: NSTextField) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 10
        wrapper.layer?.cornerCurve = .continuous
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        wrapper.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        scroll.documentView = textView
        wrapper.addSubview(scroll)

        placeholder.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        placeholder.textColor = .placeholderTextColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isSelectable = false
        wrapper.addSubview(placeholder)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: wrapper.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            placeholder.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            placeholder.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 13),
        ])
        return wrapper
    }

    // MARK: - Send (Multi-turn)

    @objc private func sendAll() {
        if isSending { stopAll(); return }

        let systemPrompt = systemPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPrompt = userPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty else {
            NSSound.beep()
            window?.makeFirstResponder(userPromptView)
            return
        }

        let temperature = Double(tempField.stringValue) ?? 0.7
        setSending(true)

        let enabledPanels = panels.filter(\.isEnabled)
        guard !enabledPanels.isEmpty else { setSending(false); return }

        let remaining = Atomic(enabledPanels.count)

        // Clear input for chat-style UX
        userPromptView.string = ""
        userPlaceholder.isHidden = false

        for panel in enabledPanels {
            panel.appendUserMessage(userPrompt)
            panel.startAssistantResponse()

            let messages = panel.buildAPIMessages(systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt)
            let model = panel.selectedModel
            let provider = panel.provider

            let task = Task { @MainActor in
                defer {
                    if remaining.decrement() == 0 {
                        self.setSending(false)
                        self.saveToHistory(
                            systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature
                        )
                    }
                }
                do {
                    try await LLMService.shared.stream(
                        provider: provider, model: model,
                        messages: messages, temperature: temperature
                    ) { [weak panel] token in
                        DispatchQueue.main.async {
                            guard let panel else { return }
                            if token.done {
                                panel.finishAssistantMessage(inputTokens: token.inputTokens, outputTokens: token.outputTokens)
                            } else {
                                panel.appendAssistantChunk(token.text)
                            }
                        }
                    }
                } catch is CancellationError {
                    // ignored
                } catch {
                    panel.showError(error.localizedDescription)
                }
            }
            activeTasks.append(task)
        }
    }

    private func stopAll() {
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        setSending(false)
    }

    private func setSending(_ sending: Bool) {
        isSending = sending
        sendButton?.title = sending ? " Stop " : " Send All "
        sendButton?.image = NSImage(
            systemSymbolName: sending ? "stop.fill" : "paperplane.fill",
            accessibilityDescription: nil
        )
        sendButton?.bezelColor = sending ? .systemRed : .controlAccentColor
    }

    // MARK: - New Conversation

    @objc func newConversation() {
        stopAll()
        for panel in panels { panel.clearConversation() }
        window?.subtitle = "Compare LLM responses side-by-side"
    }

    // MARK: - History

    private func saveToHistory(systemPrompt: String, userPrompt: String, temperature: Double) {
        let responses = panels.map { panel -> ProviderResponse in
            ProviderResponse(
                provider: panel.provider.rawValue,
                model: panel.selectedModel,
                messages: panel.conversationHistory,
                inputTokens: panel.lastInputTokens,
                outputTokens: panel.lastOutputTokens,
                durationSeconds: panel.lastDuration,
                error: panel.lastError
            )
        }
        let entry = HistoryEntry(
            id: UUID(), timestamp: Date(),
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            userPrompt: userPrompt, temperature: temperature,
            responses: responses
        )
        HistoryStore.shared.save(entry)
    }

    @objc private func toggleHistory(_ sender: NSButton) {
        if let popover = historyPopover, popover.isShown {
            popover.close()
            return
        }

        let controller = HistoryPanelController()
        controller.delegate = self
        historyController = controller

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 380, height: 460)
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        self.historyPopover = popover
    }

    func historyPanel(_ panel: HistoryPanelController, loadEntry entry: HistoryEntry) {
        historyPopover?.close()
        newConversation()
        if let sys = entry.systemPrompt {
            systemPromptView.string = sys
            sysPlaceholder.isHidden = true
        }
        userPromptView.string = entry.userPrompt
        userPlaceholder.isHidden = true
        tempField.stringValue = String(format: "%.1f", entry.temperature)
    }

    func historyPanel(_ panel: HistoryPanelController, resendEntry entry: HistoryEntry) {
        historyPanel(panel, loadEntry: entry)
        sendAll()
    }

    // MARK: - Export

    @objc private func showExportMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy as Markdown", action: #selector(copyAsMarkdown), keyEquivalent: "")
        menu.addItem(withTitle: "Copy as JSON", action: #selector(copyAsJSON), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save as Markdown...", action: #selector(saveAsMarkdown), keyEquivalent: "")
        menu.addItem(withTitle: "Save as JSON...", action: #selector(saveAsJSON), keyEquivalent: "")
        for item in menu.items { item.target = self }
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    private func buildSnapshot() -> ExportService.Snapshot {
        ExportService.Snapshot(
            systemPrompt: {
                let s = systemPromptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }(),
            temperature: Double(tempField.stringValue) ?? 0.7,
            timestamp: Date(),
            panels: panels.map { panel in
                ExportService.PanelSnapshot(
                    provider: panel.provider.rawValue,
                    model: panel.selectedModel,
                    messages: panel.conversationHistory,
                    inputTokens: panel.lastInputTokens,
                    outputTokens: panel.lastOutputTokens,
                    duration: panel.lastDuration
                )
            }
        )
    }

    @objc private func copyAsMarkdown() {
        ExportService.copyToClipboard(ExportService.toMarkdown(buildSnapshot()))
        flashSubtitle("Copied Markdown to clipboard")
    }

    @objc private func copyAsJSON() {
        ExportService.copyToClipboard(ExportService.toJSON(buildSnapshot()))
        flashSubtitle("Copied JSON to clipboard")
    }

    @objc private func saveAsMarkdown() {
        let md = ExportService.toMarkdown(buildSnapshot())
        ExportService.saveToFile(md, defaultName: "prompt-workbench-comparison.md", fileType: "md")
    }

    @objc private func saveAsJSON() {
        let json = ExportService.toJSON(buildSnapshot())
        ExportService.saveToFile(json, defaultName: "prompt-workbench-comparison.json", fileType: "json")
    }

    private func flashSubtitle(_ msg: String) {
        let original = window?.subtitle ?? ""
        window?.subtitle = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.window?.subtitle = original
        }
    }
}

// MARK: - Placeholder visibility

extension MainWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if tv === systemPromptView {
            sysPlaceholder.isHidden = !tv.string.isEmpty
        } else if tv === userPromptView {
            userPlaceholder.isHidden = !tv.string.isEmpty
        }
    }
}

// MARK: - Thread-safe counter

final class Atomic: @unchecked Sendable {
    private var value: Int
    private let lock = NSLock()
    init(_ value: Int) { self.value = value }
    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value -= 1
        return value
    }
}
