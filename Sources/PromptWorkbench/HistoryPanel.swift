import AppKit

protocol HistoryPanelDelegate: AnyObject {
    func historyPanel(_ panel: HistoryPanelController, loadEntry entry: HistoryEntry)
    func historyPanel(_ panel: HistoryPanelController, resendEntry entry: HistoryEntry)
}

final class HistoryPanelController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: HistoryPanelDelegate?

    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private var filteredEntries: [HistoryEntry] = []
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 460))
        self.view = container
        setupUI(in: container)
        reload()
    }

    func reload() {
        filteredEntries = HistoryStore.shared.allEntries
        tableView.reloadData()
    }

    private func setupUI(in container: NSView) {
        // Search
        searchField.placeholderString = "Search prompts..."
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchField)

        // Table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let promptCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("prompt"))
        promptCol.title = "Prompt"
        promptCol.width = 220
        tableView.addTableColumn(promptCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Date"
        dateCol.width = 100
        tableView.addTableColumn(dateCol)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 36
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        scrollView.documentView = tableView
        container.addSubview(scrollView)

        // Buttons
        let loadBtn = NSButton(title: "Load Prompt", target: self, action: #selector(loadSelected))
        loadBtn.bezelStyle = .rounded
        loadBtn.translatesAutoresizingMaskIntoConstraints = false

        let resendBtn = NSButton(title: "Re-send", target: self, action: #selector(resendSelected))
        resendBtn.bezelStyle = .rounded
        resendBtn.bezelColor = .controlAccentColor
        resendBtn.translatesAutoresizingMaskIntoConstraints = false

        let deleteBtn = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!,
            target: self, action: #selector(deleteSelected)
        )
        deleteBtn.bezelStyle = .toolbar
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnRow = NSStackView(views: [deleteBtn, NSView(), loadBtn, resendBtn])
        btnRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(btnRow)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -8),

            btnRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            btnRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            btnRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            btnRow.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    // MARK: - Data Source

    func numberOfRows(in tableView: NSTableView) -> Int { filteredEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let cell = NSTextField(labelWithString: "")
        cell.lineBreakMode = .byTruncatingTail

        if id.rawValue == "prompt" {
            cell.stringValue = entry.userPrompt.replacingOccurrences(of: "\n", with: " ")
            cell.font = .systemFont(ofSize: 12, weight: .regular)
        } else {
            cell.stringValue = dateFormatter.string(from: entry.timestamp)
            cell.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            cell.textColor = .secondaryLabelColor
        }
        return cell
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        filteredEntries = HistoryStore.shared.search(searchField.stringValue)
        tableView.reloadData()
    }

    @objc private func loadSelected() {
        guard tableView.selectedRow >= 0 else { return }
        delegate?.historyPanel(self, loadEntry: filteredEntries[tableView.selectedRow])
    }

    @objc private func resendSelected() {
        guard tableView.selectedRow >= 0 else { return }
        delegate?.historyPanel(self, resendEntry: filteredEntries[tableView.selectedRow])
    }

    @objc private func deleteSelected() {
        guard tableView.selectedRow >= 0 else { return }
        let entry = filteredEntries[tableView.selectedRow]
        HistoryStore.shared.delete(id: entry.id)
        reload()
    }
}
