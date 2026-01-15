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
            if !AerospaceAPI.ensureEnabled() {
                fputs("Could not enable aerospace, exiting\n", stderr)
                NSApp.terminate(nil)
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
        HotkeyManager.shared.register()

        fputs("Daemon running.\n", stderr)
    }

    private func handleExpand() {
        // If window is visible in compact mode, expand it with animation
        if let window = workspaceWindow, window.isVisible, window.mode == .compact {
            window.expand()
        }
    }

    private func handleBack() {
        let (order, current) = WorkspaceNavigator.shared.back()
        guard !order.isEmpty else { return }
        showOrUpdateWorkspaceWindow(workspaces: order, current: current)
    }

    private func handleForward() {
        let (order, current) = WorkspaceNavigator.shared.forward()
        guard !order.isEmpty else { return }
        showOrUpdateWorkspaceWindow(workspaces: order, current: current)
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
        workspaceWindow?.show(workspaces: ordered, current: currentWs, autoHide: autoHide && !expanded)

        if expanded {
            // Small delay so initial layout happens first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.workspaceWindow?.expand()
            }
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
}
