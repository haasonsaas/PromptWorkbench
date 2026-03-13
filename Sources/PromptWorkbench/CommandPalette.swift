import AppKit

struct Command {
    let name: String
    let icon: String          // SF Symbol name
    let shortcut: String      // display hint like "⌘↩"
    let section: String       // grouping: "Actions", "Providers", "Export"
    let action: () -> Void
}

final class CommandPaletteController: NSObject {
    private var panel: NSPanel?
    private var commands: [Command] = []
    private var filtered: [Command] = []
    private var tableView: NSTableView!
    private var searchField: NSTextField!
    private var selectedRow = 0

    static let shared = CommandPaletteController()
    private override init() { super.init() }

    var isVisible: Bool { panel?.isVisible ?? false }

    func register(_ commands: [Command]) {
        self.commands = commands
    }

    func toggle(relativeTo window: NSWindow?) {
        if let panel, panel.isVisible {
            dismiss()
        } else {
            show(relativeTo: window)
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Show

    private func show(relativeTo window: NSWindow?) {
        filtered = commands
        selectedRow = 0

        let palette = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        palette.isFloatingPanel = true
        palette.level = .floating
        palette.hasShadow = true
        palette.backgroundColor = .clear
        palette.isMovableByWindowBackground = false
        palette.isReleasedWhenClosed = false

        let content = buildContent()
        palette.contentView = content

        // Center above the parent window
        if let parentFrame = window?.frame {
            let x = parentFrame.midX - 260
            let y = parentFrame.midY + 40
            palette.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            palette.center()
        }

        self.panel = palette
        palette.makeKeyAndOrderFront(nil)
        palette.makeFirstResponder(searchField)
    }

    // MARK: - UI

    private func buildContent() -> NSView {
        // Outer container with rounded corners and shadow
        let outer = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
        outer.wantsLayer = true
        outer.layer?.cornerRadius = 14
        outer.layer?.cornerCurve = .continuous
        outer.layer?.masksToBounds = true

        // Vibrancy background
        let vibrancy = NSVisualEffectView(frame: outer.bounds)
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.autoresizingMask = [.width, .height]
        outer.addSubview(vibrancy)

        // Search field
        searchField = NSTextField()
        searchField.placeholderString = "Type a command..."
        searchField.font = .systemFont(ofSize: 18, weight: .regular)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = .labelColor
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let searchIcon = NSImageView()
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            searchIcon.image = img.withSymbolConfiguration(cfg)
            searchIcon.contentTintColor = .tertiaryLabelColor
        }
        searchIcon.translatesAutoresizingMaskIntoConstraints = false

        let searchRow = NSView()
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchRow.addSubview(searchIcon)
        searchRow.addSubview(searchField)
        vibrancy.addSubview(searchRow)

        // Separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(sep)

        // Results table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        col.width = 500
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(executeSelected)
        tableView.target = self

        scrollView.documentView = tableView
        vibrancy.addSubview(scrollView)

        // Hint bar
        let hint = NSTextField(labelWithString: "↑↓ Navigate  ↩ Execute  esc Dismiss")
        hint.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(hint)

        NSLayoutConstraint.activate([
            searchRow.topAnchor.constraint(equalTo: vibrancy.topAnchor, constant: 12),
            searchRow.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor, constant: 16),
            searchRow.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor, constant: -16),
            searchRow.heightAnchor.constraint(equalToConstant: 32),

            searchIcon.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            searchIcon.leadingAnchor.constraint(equalTo: searchRow.leadingAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 20),

            searchField.centerYAnchor.constraint(equalTo: searchRow.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchRow.trailingAnchor),

            sep.topAnchor.constraint(equalTo: searchRow.bottomAnchor, constant: 10),
            sep.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor, constant: 12),
            sep.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor, constant: -12),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -4),

            hint.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor, constant: -8),
            hint.heightAnchor.constraint(equalToConstant: 18),
        ])

        return outer
    }

    // MARK: - Filtering

    private func filter(_ query: String) {
        if query.isEmpty {
            filtered = commands
        } else {
            let q = query.lowercased()
            filtered = commands.filter { cmd in
                cmd.name.lowercased().contains(q) ||
                cmd.section.lowercased().contains(q)
            }
        }
        selectedRow = 0
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func executeSelected() {
        guard selectedRow >= 0, selectedRow < filtered.count else { return }
        let cmd = filtered[selectedRow]
        dismiss()
        cmd.action()
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedRow = max(0, min(filtered.count - 1, selectedRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedRow)
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        filter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            executeSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension CommandPaletteController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cmd = filtered[row]
        let cell = NSView()

        let icon = NSImageView()
        if let img = NSImage(systemSymbolName: cmd.icon, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            icon.image = img.withSymbolConfiguration(cfg)
            icon.contentTintColor = .secondaryLabelColor
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)

        let name = NSTextField(labelWithString: cmd.name)
        name.font = .systemFont(ofSize: 13, weight: .regular)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(name)

        let section = NSTextField(labelWithString: cmd.section)
        section.font = .systemFont(ofSize: 10, weight: .medium)
        section.textColor = .tertiaryLabelColor
        section.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(section)

        let shortcut = NSTextField(labelWithString: cmd.shortcut)
        shortcut.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        shortcut.textColor = .tertiaryLabelColor
        shortcut.alignment = .right
        shortcut.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(shortcut)

        NSLayoutConstraint.activate([
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 18),

            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),

            section.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            section.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),

            shortcut.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedRow = tableView.selectedRow
    }
}
