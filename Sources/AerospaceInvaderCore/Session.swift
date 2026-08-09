import Cocoa
import Foundation

/// A single user intent — whether it originated from a CLI argument or a global hotkey.
/// This is the seam AppDelegate, main.swift, and HotkeyManager all translate *into*,
/// so Session is the one place that decides what each intent does.
public enum UserIntent: Equatable {
    case runDaemon
    case showTabs
    case showExpanded
    case whichKey(mode: String)
    case hide
    case navigateBack
    case navigateForward
    case navigateToggle
    case toggleExpand
    case selectWorkspace(String)
}

/// Deep module that owns the entire user-facing session: hotkey registration, window
/// lifecycle, and the stitching between WorkspaceNavigator, OrderProvider, and the OSD.
/// Callers translate events into `UserIntent` and call `execute` — they never touch
/// Navigator or Window directly. That is the depth: one interface, all session behaviour
/// behind it.
///
/// Two adapters justify the seam today: AppKit in production and in-memory fakes in tests.
public final class Session {
    private let api: AerospaceCommandExecutor
    private let navigator: WorkspaceNavigator
    private let orderProvider: WorkspaceOrderProvider
    private let hotkeyManager: HotkeyManager

    /// Factory for OSD windows — injected so tests can supply a spy without creating a real NSPanel.
    private let windowFactory: () -> WorkspaceWindow
    /// Factory for which-key windows.
    private let whichKeyFactory: (AerospaceCommandExecutor) -> WhichKeyWindow

    public var workspaceWindow: WorkspaceWindow?
    public var whichKeyWindow: WhichKeyWindow?
    /// Closure that reports whether the current session is a long-lived daemon. Used to
    /// decide window dismissal policy (daemon fades, one-shot terminates). In production
    /// this reflects AppDelegate.isDaemon; tests can inject a stub.
    private var isDaemonProvider: () -> Bool

    /// Replace the daemon provider after init (needed because AppDelegate captures self).
    func _setIsDaemonProvider(_ provider: @escaping () -> Bool) {
        isDaemonProvider = provider
    }

    public init(
        api: AerospaceCommandExecutor = AerospaceAPI.shared,
        navigator: WorkspaceNavigator = .shared,
        orderProvider: WorkspaceOrderProvider = OrderManager.shared,
        hotkeyManager: HotkeyManager = .shared,
        isDaemon: @escaping () -> Bool = { true },
        windowFactory: @escaping () -> WorkspaceWindow = { WorkspaceWindow() },
        whichKeyFactory: @escaping (AerospaceCommandExecutor) -> WhichKeyWindow = { WhichKeyWindow(api: $0) }
    ) {
        self.api = api
        self.navigator = navigator
        self.orderProvider = orderProvider
        self.hotkeyManager = hotkeyManager
        self.isDaemonProvider = isDaemon
        self.windowFactory = windowFactory
        self.whichKeyFactory = whichKeyFactory
    }

    // MARK: - Public seam

    /// Execute a user intent. This is the test surface: drive the session with mock
    /// collaborators and assert the window or navigator effects without a running NSApp.
    public func execute(_ intent: UserIntent) {
        switch intent {
        case .runDaemon: startDaemon()
        case .showTabs: showWorkspaceWindow(expanded: false, autoHide: true)
        case .showExpanded: showWorkspaceWindow(expanded: true, autoHide: false)
        case .whichKey(let mode): showWhichKey(mode: mode)
        case .hide: NSApp.terminate(nil)
        case .navigateBack: handleBack()
        case .navigateForward: handleForward()
        case .navigateToggle: handleToggle()
        case .toggleExpand: handleExpand()
        case .selectWorkspace(let ws): handleSelectWorkspace(ws)
        }
    }

    // MARK: - Daemon lifecycle

    private func startDaemon() {
        fputs("Starting aerospace-invader daemon...\n", stderr)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.navigator.refreshCache()
        }

        // All hotkeys translate into intents — Session is the single dispatch table.
        hotkeyManager.onBack = { [weak self] in self?.execute(.navigateBack) }
        hotkeyManager.onForward = { [weak self] in self?.execute(.navigateForward) }
        hotkeyManager.onExpand = { [weak self] in self?.execute(.toggleExpand) }
        hotkeyManager.onToggle = { [weak self] in self?.execute(.navigateToggle) }
        hotkeyManager.register()

        fputs("Daemon running.\n", stderr)
    }

    // MARK: - Intent handlers — one place, not four near-identical closures in AppDelegate

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

    private func handleToggle() {
        navigator.toggle { [weak self] order, current in
            guard !order.isEmpty else { return }
            self?.showOrUpdateWorkspaceWindow(workspaces: order, current: current)
        }
    }

    private func handleExpand() {
        if let window = workspaceWindow, window.isVisible {
            if window.mode == .compact { window.expand() } else { window.fadeOut() }
        } else {
            showWorkspaceWindow(expanded: true, autoHide: false)
        }
    }

    private func handleSelectWorkspace(_ workspace: String) {
        api.switchToWorkspace(workspace)
        // WorkspaceWindow's onSelectWorkspace previously decided daemon vs one-shot termination;
        // that policy now lives here: Session owns lifecycle, the window is just an adapter.
        // Callers that need one-shot termination should execute .hide after selection.
    }

    // MARK: - Window management — unified under Session, not split across AppDelegate

    private func showOrUpdateWorkspaceWindow(workspaces: [String], current: String?) {
        if workspaceWindow == nil { workspaceWindow = makeWorkspaceWindow() }
        workspaceWindow?.show(workspaces: workspaces, current: current, autoHide: true)
    }

    func makeWorkspaceWindow() -> WorkspaceWindow {
        let window = windowFactory()
        window.onSelectWorkspace = { [weak self] ws in
            guard let self = self else { return }
            self.api.switchToWorkspace(ws)
            if self.isDaemonProvider() {
                self.workspaceWindow?.fadeOut()
            } else {
                NSApp.terminate(nil)
            }
        }
        window.onOrderChanged = { [weak self] newOrder in
            self?.orderProvider.saveOrder(newOrder)
        }
        window.onCollapse = { [weak self] in
            guard self?.isDaemonProvider() == true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.workspaceWindow?.fadeOut()
            }
        }
        window.onDismiss = { [weak self] in
            guard let self = self, !self.isDaemonProvider() else { return }
            NSApp.terminate(nil)
        }
        return window
    }

    private func showWorkspaceWindow(expanded: Bool, autoHide: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let (current, currentWs) = self.api.getWorkspacesWithFocus()
            let ordered = self.orderProvider.reconcile(with: current)

            DispatchQueue.main.async {
                let window = self.makeWorkspaceWindow()
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
        let window = whichKeyFactory(api)
        whichKeyWindow = window
        if !window.show(mode: mode) { NSApp.terminate(nil) }
    }
}
