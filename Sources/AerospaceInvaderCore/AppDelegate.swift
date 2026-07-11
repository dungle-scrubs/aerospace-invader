import Cocoa

/// A command mode the app can launch in, parsed from the first CLI argument.
public enum AppMode: String {
    case daemon, tabs, expand, whichkey, hide
}

/// Application delegate — routes commands and wires dependencies.
/// Responsibilities are limited to lifecycle, mode routing, and dependency wiring.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The workspace OSD window (created lazily on first use).
    public var workspaceWindow: WorkspaceWindow?
    /// The which-key popup (created per invocation).
    public var whichKeyWindow: WhichKeyWindow?

    /// The command mode to execute.
    public var mode: AppMode = .daemon
    /// Optional argument for the mode (e.g. mode name for whichkey).
    public var modeArg: String?
    /// Whether the app is running as a persistent daemon.
    public var isDaemon: Bool { mode == .daemon }

    // Dependencies — defaulting to shared singletons
    private let api: AerospaceCommandExecutor
    private let navigator: WorkspaceNavigator
    private let orderProvider: WorkspaceOrderProvider
    private let hotkeyManager: HotkeyManager

    /// Creates an AppDelegate with injected dependencies.
    /// - Parameters:
    ///   - api: Aerospace command executor (default: shared singleton).
    ///   - navigator: Workspace navigator (default: shared singleton).
    ///   - orderProvider: Order persistence (default: shared singleton).
    ///   - hotkeyManager: Hotkey manager (default: shared singleton).
    public init(api: AerospaceCommandExecutor = AerospaceAPI.shared,
                navigator: WorkspaceNavigator = .shared,
                orderProvider: WorkspaceOrderProvider = OrderManager.shared,
                hotkeyManager: HotkeyManager = .shared) {
        self.api = api
        self.navigator = navigator
        self.orderProvider = orderProvider
        self.hotkeyManager = hotkeyManager
        super.init()
    }

    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if mode != .hide {
            switch api.ensureEnabled() {
            case .success:
                break
            case .failure(let error):
                showErrorAndExit(error)
                return
            }
        }

        switch mode {
        case .daemon:   startDaemon()
        case .tabs:     showWorkspaceWindow(expanded: false, autoHide: true)
        case .expand:   showWorkspaceWindow(expanded: true, autoHide: false)
        case .whichkey: showWhichKey(mode: modeArg ?? "service")
        case .hide:     NSApp.terminate(nil)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isDaemon
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
    }

    // MARK: - Daemon Mode

    private func startDaemon() {
        fputs("Starting aerospace-invader daemon...\n", stderr)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.navigator.refreshCache()
        }

        hotkeyManager.onBack = { [weak self] in self?.handleBack() }
        hotkeyManager.onForward = { [weak self] in self?.handleForward() }
        hotkeyManager.onExpand = { [weak self] in self?.handleExpand() }
        hotkeyManager.onToggle = { [weak self] in self?.handleToggle() }
        hotkeyManager.register()

        fputs("Daemon running.\n", stderr)
    }

    // MARK: - Hotkey Handlers

    private func handleExpand() {
        if let window = workspaceWindow, window.isVisible {
            if window.mode == .compact {
                window.expand()
            } else {
                window.fadeOut()
            }
        } else {
            showWorkspaceWindow(expanded: true, autoHide: false)
        }
    }

    private func handleToggle() {
        navigator.toggle { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func handleBack() {
        navigator.back { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func handleForward() {
        navigator.forward { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    // MARK: - Window Management

    private func showOrUpdateWorkspaceWindow(workspaces: [String], current: String?) {
        if workspaceWindow == nil {
            workspaceWindow = createWorkspaceWindow()
        }
        workspaceWindow?.show(workspaces: workspaces, current: current, autoHide: true)
    }

    private func createWorkspaceWindow() -> WorkspaceWindow {
        let window = WorkspaceWindow()
        window.onSelectWorkspace = { [weak self] ws in
            guard let self = self else { return }
            self.api.switchToWorkspace(ws)
            if self.isDaemon {
                self.workspaceWindow?.fadeOut()
            } else {
                NSApp.terminate(nil)
            }
        }
        window.onOrderChanged = { [weak self] newOrder in
            self?.orderProvider.saveOrder(newOrder)
        }
        window.onCollapse = { [weak self] in
            guard self?.isDaemon == true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.workspaceWindow?.fadeOut()
            }
        }
        window.onDismiss = { [weak self] in
            // A hidden window never closes itself, so a one-shot (non-daemon) invocation would
            // otherwise leave a resident process behind. Terminate once the OSD is dismissed.
            guard let self = self, !self.isDaemon else { return }
            NSApp.terminate(nil)
        }
        return window
    }

    private func showWorkspaceWindow(expanded: Bool, autoHide: Bool) {
        // The workspace query blocks on the aerospace CLI; run it off the main thread and
        // build/show the window back on main. A single query yields both list and focus,
        // avoiding a redundant second subprocess.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let (current, currentWs) = self.api.getWorkspacesWithFocus()
            let ordered = self.orderProvider.reconcile(with: current)

            DispatchQueue.main.async {
                let window = self.createWorkspaceWindow()
                self.workspaceWindow = window
                if expanded {
                    window.showExpanded(workspaces: ordered, current: currentWs)
                } else {
                    window.show(workspaces: ordered, current: currentWs, autoHide: autoHide)
                }
            }
        }
    }

    private func showWhichKey(mode: String) {
        let window = WhichKeyWindow(api: api)
        whichKeyWindow = window
        if !window.show(mode: mode) {
            // Bindings couldn't be fetched (e.g. unknown mode). This is a one-shot command with
            // no window to close, so nothing would ever terminate the process — exit now.
            NSApp.terminate(nil)
        }
    }

    // MARK: - Error Handling

    /// Displays a critical error alert and terminates the app.
    /// - Parameter error: The aerospace error to display.
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
