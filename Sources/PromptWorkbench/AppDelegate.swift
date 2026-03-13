import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showMainWindow()
        } else {
            showOnboarding()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.onComplete = { [weak self] in
            self?.onboardingController?.close()
            self?.onboardingController = nil
            self?.showMainWindow()
        }
        onboardingController?.showWindow(nil)
    }

    private func showMainWindow() {
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Prompt Workbench", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Prompt Workbench", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Conversation", action: #selector(newConversation), keyEquivalent: "n")
        fileMenu.addItem(.separator())
        let exportItem = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        let exportSub = NSMenu()
        let mdItem = NSMenuItem(title: "Copy as Markdown", action: #selector(copyMarkdown), keyEquivalent: "C")
        mdItem.keyEquivalentModifierMask = [.command, .shift]
        exportSub.addItem(mdItem)
        let jsonItem = NSMenuItem(title: "Copy as JSON", action: #selector(copyJSON), keyEquivalent: "J")
        jsonItem.keyEquivalentModifierMask = [.command, .shift]
        exportSub.addItem(jsonItem)
        exportSub.addItem(.separator())
        let saveMdItem = NSMenuItem(title: "Save as Markdown...", action: #selector(saveMarkdown), keyEquivalent: "E")
        saveMdItem.keyEquivalentModifierMask = [.command, .shift]
        exportSub.addItem(saveMdItem)
        exportSub.addItem(withTitle: "Save as JSON...", action: #selector(saveJSON), keyEquivalent: "")
        exportItem.submenu = exportSub
        fileMenu.addItem(exportItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let histItem = NSMenuItem(title: "History", action: #selector(showHistory), keyEquivalent: "y")
        histItem.keyEquivalentModifierMask = .command
        viewMenu.addItem(histItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Menu Actions (forwarded to MainWindowController)

    @objc func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func newConversation() { mainWindowController?.newConversation() }
    @objc private func showHistory() { /* triggered via responder chain or toolbar */ }
    @objc private func copyMarkdown() { mainWindowController?.perform(Selector(("copyAsMarkdown"))) }
    @objc private func copyJSON() { mainWindowController?.perform(Selector(("copyAsJSON"))) }
    @objc private func saveMarkdown() { mainWindowController?.perform(Selector(("saveAsMarkdown"))) }
    @objc private func saveJSON() { mainWindowController?.perform(Selector(("saveAsJSON"))) }
}
