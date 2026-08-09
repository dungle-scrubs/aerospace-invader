import Cocoa

/// A command mode the app can launch in, parsed from the first CLI argument.
public enum AppMode: String {
    case daemon, tabs, expand, whichkey, hide
}

/// Application delegate — now a thin adapter that translates `AppMode` into `UserIntent`
/// and delegates to `Session`. Session is the deep module that owns window lifecycle,
/// hotkey dispatch, and the stitching between Navigator and the OSD. The delegate keeps
/// only lifecycle (ensureEnabled, error alert) and the NSApplicationDelegate conformance.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The workspace OSD window (proxied from Session for backward compatibility).
    public var workspaceWindow: WorkspaceWindow? {
        get { session.workspaceWindow }
        set { session.workspaceWindow = newValue }
    }
    /// The which-key popup (proxied from Session).
    public var whichKeyWindow: WhichKeyWindow? {
        get { session.whichKeyWindow }
        set { session.whichKeyWindow = newValue }
    }

    /// The command mode to execute.
    public var mode: AppMode = .daemon
    /// Optional argument for the mode (e.g. mode name for whichkey).
    public var modeArg: String?
    /// Whether the app is running as a persistent daemon.
    public var isDaemon: Bool { mode == .daemon }

    private let api: AerospaceCommandExecutor
    private let hotkeyManager: HotkeyManager
    let session: Session

    /// Creates an AppDelegate with injected dependencies.
    /// - Parameters:
    ///   - api: Aerospace command executor (default: shared singleton).
    ///   - navigator: Workspace navigator (default: shared singleton).
    ///   - orderProvider: Order persistence (default: shared singleton).
    ///   - hotkeyManager: Hotkey manager (default: shared singleton).
    ///   - windowFactory: Factory for OSD windows (for testing).
    ///   - whichKeyFactory: Factory for which-key windows (for testing).
    public init(
        api: AerospaceCommandExecutor = AerospaceAPI.shared,
        navigator: WorkspaceNavigator = .shared,
        orderProvider: WorkspaceOrderProvider = OrderManager.shared,
        hotkeyManager: HotkeyManager = .shared,
        windowFactory: @escaping () -> WorkspaceWindow = { WorkspaceWindow() },
        whichKeyFactory: @escaping (AerospaceCommandExecutor) -> WhichKeyWindow = { WhichKeyWindow(api: $0) }
    ) {
        self.api = api
        self.hotkeyManager = hotkeyManager
        self.session = Session(
            api: api,
            navigator: navigator,
            orderProvider: orderProvider,
            hotkeyManager: hotkeyManager,
            isDaemon: { false },  // placeholder — will be replaced after super.init so it can capture self
            windowFactory: windowFactory,
            whichKeyFactory: whichKeyFactory
        )
        super.init()
        // Rebind isDaemon to reflect the live delegate state, not a captured constant.
        self.session.replaceIsDaemonProvider { [weak self] in self?.isDaemon ?? false }
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

        // Single seam: AppMode → UserIntent → Session.execute
        switch mode {
        case .daemon: session.execute(.runDaemon)
        case .tabs: session.execute(.showTabs)
        case .expand: session.execute(.showExpanded)
        case .whichkey: session.execute(.whichKey(mode: modeArg ?? "service"))
        case .hide: session.execute(.hide)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isDaemon
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
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

// MARK: - Session isDaemon rebinding

extension Session {
    /// Replace the isDaemon provider after initialization. AppDelegate needs this because
    /// the provider must capture `self.isDaemon` which isn't available until after `super.init`.
    fileprivate func replaceIsDaemonProvider(_ provider: @escaping () -> Bool) {
        // Session stores the closure in a private let; use reflection via a dedicated update
        // method rather than exposing the closure. We add this as a private extension to avoid
        // making the property internal.
        // Swift cannot reassign a let via extension, so we expose a dedicated internal setter.
        // Fall back to using a mutable boxed reference.
        _setIsDaemonProvider(provider)
    }
}
