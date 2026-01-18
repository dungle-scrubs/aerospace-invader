import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate {
    public var workspaceWindow: WorkspaceWindow?
    public var whichKeyWindow: WhichKeyWindow?

    public var mode: String = "daemon"
    public var modeArg: String?
    public var isDaemon: Bool { mode == "daemon" }

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure aerospace is running (except for hide command)
        if mode != "hide" {
            switch AerospaceAPI.ensureEnabled() {
            case .success:
                break
            case .failure(let error):
                showErrorAndExit(error)
                return
            }
        }

        switch mode {
        case "daemon":
            startDaemon()
        case "tabs":
            showWorkspaceWindow(expanded: false, autoHide: true)
        case "expand":
            showWorkspaceWindow(expanded: true, autoHide: false)
        case "whichkey":
            showWhichKey(mode: modeArg ?? "service")
        case "hide":
            NSApp.terminate(nil)
        default:
            fputs("Unknown mode: \(mode)\n", stderr)
            fputs("Usage: aerospace-invader [daemon|tabs|expand|whichkey <mode>]\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func startDaemon() {
        fputs("Starting aerospace-invader daemon...\n", stderr)

        // Pre-populate cache in background
        DispatchQueue.global(qos: .userInitiated).async {
            WorkspaceNavigator.shared.refreshCache()
        }

        // Register hotkeys
        HotkeyManager.shared.onBack = { [weak self] in
            self?.handleBack()
        }
        HotkeyManager.shared.onForward = { [weak self] in
            self?.handleForward()
        }
        HotkeyManager.shared.onExpand = { [weak self] in
            self?.handleExpand()
        }
        HotkeyManager.shared.onRefresh = { [weak self] in
            self?.handleRefresh()
        }
        HotkeyManager.shared.register()

        fputs("Daemon running.\n", stderr)
    }

    private func handleExpand() {
        // If window is visible, toggle based on current mode
        if let window = workspaceWindow, window.isVisible {
            if window.mode == .compact {
                window.expand()
            } else {
                window.fadeOut()
            }
        } else {
            // Show expanded view directly
            showWorkspaceWindow(expanded: true, autoHide: false)
        }
    }

    private func handleRefresh() {
        WorkspaceNavigator.shared.toggle { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func handleBack() {
        WorkspaceNavigator.shared.back { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func handleForward() {
        WorkspaceNavigator.shared.forward { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func showOrUpdateWorkspaceWindow(workspaces: [String], current: String?) {
        if workspaceWindow == nil {
            workspaceWindow = createWorkspaceWindow()
        }
        workspaceWindow?.show(workspaces: workspaces, current: current, autoHide: true)
    }

    private func createWorkspaceWindow() -> WorkspaceWindow {
        let window = WorkspaceWindow()
        window.onSelectWorkspace = { [weak self] ws in
            AerospaceAPI.switchToWorkspace(ws)
            if self?.isDaemon == true {
                self?.workspaceWindow?.fadeOut()
            } else {
                NSApp.terminate(nil)
            }
        }
        window.onOrderChanged = { newOrder in
            OrderManager.shared.saveOrder(newOrder)
        }
        window.onCollapse = { [weak self] in
            // In daemon mode, fade out after collapse animation
            if self?.isDaemon == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.workspaceWindow?.fadeOut()
                }
            }
        }
        return window
    }

    private func showWorkspaceWindow(expanded: Bool, autoHide: Bool) {
        let current = AerospaceAPI.getNonEmptyWorkspaces()
        let ordered = OrderManager.shared.mergeWithCurrent(current)
        OrderManager.shared.saveOrder(ordered)
        let currentWs = AerospaceAPI.getCurrentWorkspace()

        workspaceWindow = createWorkspaceWindow()

        if expanded {
            workspaceWindow?.showExpanded(workspaces: ordered, current: currentWs)
        } else {
            workspaceWindow?.show(workspaces: ordered, current: currentWs, autoHide: autoHide)
        }
    }

    private func showWhichKey(mode: String) {
        whichKeyWindow = WhichKeyWindow()
        whichKeyWindow?.show(mode: mode)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Daemon keeps running even with no windows
        return !isDaemon
    }

    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
    }

    private func showErrorAndExit(_ error: AerospaceError) {
        fputs("\(error)\n", stderr)

        let alert = NSAlert()
        alert.messageText = "AeroSpace Error"
        alert.informativeText = error.description
        alert.alertStyle = .critical

        if case .notInstalled = error {
            alert.addButton(withTitle: "Open Installation Page")
            alert.addButton(withTitle: "Quit")
        } else {
            alert.addButton(withTitle: "Quit")
        }

        // Temporarily become a regular app to show the alert
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        if case .notInstalled = error, response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/nikitabobko/AeroSpace#installation") {
                NSWorkspace.shared.open(url)
            }
        }

        NSApp.terminate(nil)
    }
}
