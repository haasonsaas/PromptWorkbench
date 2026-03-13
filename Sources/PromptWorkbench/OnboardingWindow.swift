import AppKit

final class OnboardingWindowController: NSWindowController {
    private var currentStep = 0
    private let totalSteps = 4
    private var contentContainer: NSView!
    private var dots: [NSView] = []
    private var backBtn: NSButton!
    private var nextBtn: NSButton!
    private var currentStepView: NSView?

    // Collected data
    private var keyFields: [LLMProvider: NSSecureTextField] = [:]
    private var sysPromptView: NSTextView!
    private var tempSlider: NSSlider!
    private var tempValueLabel: NSTextField!

    var onComplete: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        self.init(window: window)
        setupChrome()
        showStep(0, forward: true)
    }

    // MARK: - Chrome (dots + buttons)

    private func setupChrome() {
        guard let cv = window?.contentView else { return }
        cv.wantsLayer = true

        contentContainer = NSView()
        contentContainer.wantsLayer = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(contentContainer)

        // Dot indicators
        let dotsStack = NSStackView()
        dotsStack.spacing = 8
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<totalSteps {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dots.append(dot)
            dotsStack.addArrangedSubview(dot)
        }
        cv.addSubview(dotsStack)

        // Navigation buttons
        backBtn = NSButton(title: "Back", target: self, action: #selector(goBack))
        backBtn.bezelStyle = .rounded
        backBtn.translatesAutoresizingMaskIntoConstraints = false

        nextBtn = NSButton(title: "Get Started", target: self, action: #selector(goNext))
        nextBtn.bezelStyle = .rounded
        nextBtn.bezelColor = .controlAccentColor
        nextBtn.keyEquivalent = "\r"
        nextBtn.font = .systemFont(ofSize: 13, weight: .semibold)
        nextBtn.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(backBtn)
        cv.addSubview(nextBtn)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: cv.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: dotsStack.topAnchor, constant: -16),

            dotsStack.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            dotsStack.bottomAnchor.constraint(equalTo: backBtn.topAnchor, constant: -16),

            backBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
            backBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),

            nextBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
            nextBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
            nextBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    // MARK: - Step Management

    private func showStep(_ step: Int, forward: Bool) {
        currentStep = step
        updateDots()
        updateButtons()

        let newView = buildStep(step)
        newView.translatesAutoresizingMaskIntoConstraints = false

        if let old = currentStepView {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = forward ? .fromRight : .fromLeft
            transition.duration = 0.25
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentContainer.layer?.add(transition, forKey: "step")
            old.removeFromSuperview()
        }

        contentContainer.addSubview(newView)
        NSLayoutConstraint.activate([
            newView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            newView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            newView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            newView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        currentStepView = newView
    }

    private func updateDots() {
        for (i, dot) in dots.enumerated() {
            if i == currentStep {
                dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            } else if i < currentStep {
                dot.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            } else {
                dot.layer?.backgroundColor = NSColor.separatorColor.cgColor
            }
        }
    }

    private func updateButtons() {
        backBtn.isHidden = currentStep == 0
        switch currentStep {
        case 0: nextBtn.title = "  Get Started  "
        case 1: nextBtn.title = "  Continue  "
        case 2: nextBtn.title = "  Continue  "
        case 3:
            nextBtn.title = "  Open Workbench  "
            nextBtn.bezelColor = NSColor(red: 0.25, green: 0.75, blue: 0.55, alpha: 1.0)
        default: break
        }
    }

    @objc private func goNext() {
        if currentStep == 1 { saveAPIKeys() }
        if currentStep == 2 { savePreferences() }
        if currentStep < totalSteps - 1 {
            showStep(currentStep + 1, forward: true)
        } else {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            onComplete?()
        }
    }

    @objc private func goBack() {
        if currentStep > 0 {
            showStep(currentStep - 1, forward: false)
        }
    }

    // MARK: - Build Steps

    private func buildStep(_ step: Int) -> NSView {
        switch step {
        case 0: return buildWelcomeStep()
        case 1: return buildKeysStep()
        case 2: return buildCustomizeStep()
        case 3: return buildReadyStep()
        default: return NSView()
        }
    }

    // -- Step 0: Welcome --

    private func buildWelcomeStep() -> NSView {
        let v = NSView()

        let icon = makeHeroIcon("rectangle.3.group.fill", size: 44, color: .controlAccentColor)
        let title = makeTitle("Welcome to Prompt Workbench")
        let subtitle = makeSubtitle("Send the same prompt to multiple LLM providers\nand compare their responses side-by-side in real time.")

        // Feature pills
        let features: [(String, String)] = [
            ("bolt.fill", "Real-time Streaming"),
            ("square.split.2x1.fill", "Side-by-Side Compare"),
            ("arrow.triangle.branch", "3 Providers"),
        ]

        let featureStack = NSStackView()
        featureStack.spacing = 12
        featureStack.translatesAutoresizingMaskIntoConstraints = false

        for (symbol, label) in features {
            let card = makeFeatureCard(symbol: symbol, label: label)
            featureStack.addArrangedSubview(card)
        }

        for sub in [icon, title, subtitle, featureStack] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 60),
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            subtitle.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            featureStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 36),
            featureStack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])

        return v
    }

    private func makeFeatureCard(symbol: String, label: String) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.cornerCurve = .continuous
        card.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = .controlAccentColor
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(icon)

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11.5, weight: .medium)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(lbl)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 155),
            card.heightAnchor.constraint(equalToConstant: 72),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            icon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            lbl.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            lbl.centerXAnchor.constraint(equalTo: card.centerXAnchor),
        ])

        return card
    }

    // -- Step 1: API Keys --

    private func buildKeysStep() -> NSView {
        let v = NSView()

        let icon = makeHeroIcon("key.fill", size: 36, color: .systemOrange)
        let title = makeTitle("Connect Your Providers")
        let subtitle = makeSubtitle("Add API keys for the providers you want to use.\nYou only need one to get started.")

        let keysStack = NSStackView()
        keysStack.orientation = .vertical
        keysStack.spacing = 14
        keysStack.translatesAutoresizingMaskIntoConstraints = false

        for provider in LLMProvider.allCases {
            let row = makeKeyRow(provider: provider)
            keysStack.addArrangedSubview(row)
        }

        for sub in [icon, title, subtitle, keysStack] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 48),
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            keysStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28),
            keysStack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),
            keysStack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -40),
        ])

        return v
    }

    private func makeKeyRow(provider: LLMProvider) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 10
        row.layer?.cornerCurve = .continuous
        row.layer?.backgroundColor = provider.accentColor.withAlphaComponent(0.06).cgColor
        row.layer?.borderWidth = 0.5
        row.layer?.borderColor = provider.accentColor.withAlphaComponent(0.2).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = provider.accentColor.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(dot)

        let name = NSTextField(labelWithString: provider.rawValue)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(name)

        let field = NSSecureTextField()
        field.placeholderString = "Paste API key..."
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.stringValue = provider.apiKey ?? ""
        field.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(field)
        keyFields[provider] = field

        let link = NSButton(title: "Get key ↗", target: self, action: #selector(openKeyLink(_:)))
        link.bezelStyle = .recessed
        link.isBordered = false
        link.font = .systemFont(ofSize: 11, weight: .medium)
        link.contentTintColor = provider.accentColor
        link.tag = LLMProvider.allCases.firstIndex(of: provider) ?? 0
        link.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(link)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 52),

            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            name.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 10),
            name.widthAnchor.constraint(equalToConstant: 90),

            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: link.leadingAnchor, constant: -8),

            link.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            link.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            link.widthAnchor.constraint(equalToConstant: 70),
        ])

        return row
    }

    @objc private func openKeyLink(_ sender: NSButton) {
        let urls = [
            "https://console.anthropic.com/settings/keys",
            "https://platform.openai.com/api-keys",
            "https://openrouter.ai/settings/keys",
        ]
        if let url = URL(string: urls[sender.tag]) {
            NSWorkspace.shared.open(url)
        }
    }

    // -- Step 2: Customize --

    private func buildCustomizeStep() -> NSView {
        let v = NSView()

        let icon = makeHeroIcon("gearshape.2.fill", size: 36, color: .systemPurple)
        let title = makeTitle("Make It Yours")
        let subtitle = makeSubtitle("Set a default system prompt and temperature\nthat pre-fill every session.")

        // System prompt
        let sysLabel = NSTextField(labelWithString: "DEFAULT SYSTEM PROMPT")
        sysLabel.font = .systemFont(ofSize: 10, weight: .bold)
        sysLabel.textColor = .tertiaryLabelColor
        sysLabel.attributedStringValue = NSAttributedString(
            string: "DEFAULT SYSTEM PROMPT",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.2 as CGFloat,
            ]
        )
        sysLabel.translatesAutoresizingMaskIntoConstraints = false

        let sysScroll = NSScrollView()
        sysScroll.hasVerticalScroller = true
        sysScroll.borderType = .noBorder
        sysScroll.drawsBackground = false
        sysScroll.autohidesScrollers = true
        sysScroll.wantsLayer = true
        sysScroll.layer?.cornerRadius = 8
        sysScroll.layer?.borderWidth = 0.5
        sysScroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        sysScroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5).cgColor
        sysScroll.translatesAutoresizingMaskIntoConstraints = false

        sysPromptView = NSTextView()
        sysPromptView.isRichText = false
        sysPromptView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sysPromptView.drawsBackground = false
        sysPromptView.textContainerInset = NSSize(width: 8, height: 8)
        sysPromptView.autoresizingMask = [.width]
        sysPromptView.isVerticallyResizable = true
        sysPromptView.textContainer?.widthTracksTextView = true
        sysPromptView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        sysScroll.documentView = sysPromptView

        // Template chips
        let templates = [
            "You are a concise expert software engineer.",
            "You are a helpful assistant. Be clear and direct.",
            "Be concise. No filler. Code over prose.",
        ]
        let chipStack = NSStackView()
        chipStack.spacing = 8
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        for (i, tpl) in templates.enumerated() {
            let chip = NSButton(title: tpl, target: self, action: #selector(applyTemplate(_:)))
            chip.bezelStyle = .recessed
            chip.font = .systemFont(ofSize: 10.5, weight: .medium)
            chip.tag = i
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 4
            chipStack.addArrangedSubview(chip)
        }

        // Temperature
        let tempLabel = NSTextField(labelWithString: "DEFAULT TEMPERATURE")
        tempLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tempLabel.textColor = .tertiaryLabelColor
        tempLabel.attributedStringValue = NSAttributedString(
            string: "DEFAULT TEMPERATURE",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 1.2 as CGFloat,
            ]
        )
        tempLabel.translatesAutoresizingMaskIntoConstraints = false

        let tempRow = NSView()
        tempRow.translatesAutoresizingMaskIntoConstraints = false

        tempSlider = NSSlider(value: 0.7, minValue: 0.0, maxValue: 2.0, target: self, action: #selector(tempSliderChanged(_:)))
        tempSlider.translatesAutoresizingMaskIntoConstraints = false

        tempValueLabel = NSTextField(labelWithString: "0.7")
        tempValueLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        tempValueLabel.textColor = .secondaryLabelColor
        tempValueLabel.alignment = .center
        tempValueLabel.translatesAutoresizingMaskIntoConstraints = false

        let lowLabel = NSTextField(labelWithString: "Precise")
        lowLabel.font = .systemFont(ofSize: 10, weight: .medium)
        lowLabel.textColor = .tertiaryLabelColor
        lowLabel.translatesAutoresizingMaskIntoConstraints = false

        let highLabel = NSTextField(labelWithString: "Creative")
        highLabel.font = .systemFont(ofSize: 10, weight: .medium)
        highLabel.textColor = .tertiaryLabelColor
        highLabel.translatesAutoresizingMaskIntoConstraints = false

        for sub in [tempSlider!, tempValueLabel!, lowLabel, highLabel] {
            tempRow.addSubview(sub)
        }

        for sub in [icon, title, subtitle, sysLabel, sysScroll, chipStack, tempLabel, tempRow] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 36),
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            sysLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 22),
            sysLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 44),

            sysScroll.topAnchor.constraint(equalTo: sysLabel.bottomAnchor, constant: 6),
            sysScroll.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),
            sysScroll.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -40),
            sysScroll.heightAnchor.constraint(equalToConstant: 64),

            chipStack.topAnchor.constraint(equalTo: sysScroll.bottomAnchor, constant: 8),
            chipStack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),

            tempLabel.topAnchor.constraint(equalTo: chipStack.bottomAnchor, constant: 20),
            tempLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 44),

            tempRow.topAnchor.constraint(equalTo: tempLabel.bottomAnchor, constant: 8),
            tempRow.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),
            tempRow.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -40),
            tempRow.heightAnchor.constraint(equalToConstant: 36),

            tempSlider.centerYAnchor.constraint(equalTo: tempRow.centerYAnchor),
            tempSlider.leadingAnchor.constraint(equalTo: tempRow.leadingAnchor, constant: 50),
            tempSlider.trailingAnchor.constraint(equalTo: tempRow.trailingAnchor, constant: -70),

            tempValueLabel.centerYAnchor.constraint(equalTo: tempRow.centerYAnchor),
            tempValueLabel.trailingAnchor.constraint(equalTo: tempRow.trailingAnchor),
            tempValueLabel.widthAnchor.constraint(equalToConstant: 50),

            lowLabel.centerYAnchor.constraint(equalTo: tempRow.centerYAnchor),
            lowLabel.trailingAnchor.constraint(equalTo: tempSlider.leadingAnchor, constant: -6),

            highLabel.centerYAnchor.constraint(equalTo: tempRow.centerYAnchor),
            highLabel.leadingAnchor.constraint(equalTo: tempSlider.trailingAnchor, constant: 6),
        ])

        return v
    }

    @objc private func applyTemplate(_ sender: NSButton) {
        let templates = [
            "You are a concise expert software engineer.",
            "You are a helpful assistant. Be clear and direct.",
            "Be concise. No filler. Code over prose.",
        ]
        sysPromptView.string = templates[sender.tag]
    }

    @objc private func tempSliderChanged(_ sender: NSSlider) {
        tempValueLabel.stringValue = String(format: "%.1f", sender.doubleValue)
    }

    // -- Step 3: Ready --

    private func buildReadyStep() -> NSView {
        let v = NSView()

        let icon = makeHeroIcon("checkmark.circle.fill", size: 48, color: NSColor(red: 0.25, green: 0.75, blue: 0.55, alpha: 1.0))
        let title = makeTitle("You're All Set")
        let subtitle = makeSubtitle("Your workbench is configured and ready to go.\nYou can change settings anytime with ⌘,")

        // Provider status summary
        let summaryStack = NSStackView()
        summaryStack.orientation = .vertical
        summaryStack.spacing = 10
        summaryStack.alignment = .leading
        summaryStack.translatesAutoresizingMaskIntoConstraints = false

        for provider in LLMProvider.allCases {
            let hasKey = !(keyFields[provider]?.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                || (provider.apiKey != nil && !provider.apiKey!.isEmpty)
            let row = NSStackView()
            row.spacing = 8

            let status = NSTextField(labelWithString: hasKey ? "✓" : "—")
            status.font = .systemFont(ofSize: 14, weight: .bold)
            status.textColor = hasKey ? NSColor(red: 0.25, green: 0.75, blue: 0.55, alpha: 1.0) : .tertiaryLabelColor

            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = provider.accentColor.cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

            let label = NSTextField(labelWithString: provider.rawValue)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = hasKey ? .labelColor : .tertiaryLabelColor

            let detail = NSTextField(labelWithString: hasKey ? "Connected" : "Not configured")
            detail.font = .systemFont(ofSize: 12, weight: .regular)
            detail.textColor = hasKey ? .secondaryLabelColor : .tertiaryLabelColor

            row.addArrangedSubview(status)
            row.addArrangedSubview(dot)
            row.addArrangedSubview(label)
            row.addArrangedSubview(detail)
            summaryStack.addArrangedSubview(row)
        }

        for sub in [icon, title, subtitle, summaryStack] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(sub)
        }

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 56),
            icon.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            summaryStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 32),
            summaryStack.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])

        return v
    }

    // MARK: - Shared Helpers

    private func makeHeroIcon(_ symbol: String, size: CGFloat, color: NSColor) -> NSImageView {
        let iv = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            iv.image = img.withSymbolConfiguration(cfg)
            iv.contentTintColor = color
        }
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }

    private func makeSubtitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        return label
    }

    // MARK: - Persistence

    private func saveAPIKeys() {
        for (provider, field) in keyFields {
            let val = field.stringValue.trimmingCharacters(in: .whitespaces)
            provider.apiKey = val.isEmpty ? nil : val
        }
    }

    private func savePreferences() {
        if let tv = sysPromptView, !tv.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(tv.string, forKey: "defaultSystemPrompt")
        }
        if let slider = tempSlider {
            UserDefaults.standard.set(String(format: "%.1f", slider.doubleValue), forKey: "defaultTemperature")
        }
    }
}
