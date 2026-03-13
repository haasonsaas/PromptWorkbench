import AppKit

final class SettingsWindowController: NSWindowController {
    private var fields: [LLMProvider: NSSecureTextField] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "API Keys"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])

        for provider in LLMProvider.allCases {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.backgroundColor = provider.accentColor.cgColor
            dot.layer?.cornerRadius = 5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

            let label = NSTextField(labelWithString: provider.rawValue)
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 100).isActive = true

            let field = NSSecureTextField()
            field.placeholderString = "sk-..."
            field.stringValue = provider.apiKey ?? ""
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            fields[provider] = field

            let row = NSStackView(views: [dot, label, field])
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)

            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ])
        }

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.bezelColor = .controlAccentColor
        saveBtn.keyEquivalent = "\r"
        saveBtn.font = .systemFont(ofSize: 13, weight: .medium)

        let btnContainer = NSStackView(views: [NSView(), saveBtn])
        btnContainer.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(btnContainer)
        btnContainer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    @objc private func save() {
        for (provider, field) in fields {
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            provider.apiKey = value.isEmpty ? nil : value
        }
        window?.close()
    }
}
