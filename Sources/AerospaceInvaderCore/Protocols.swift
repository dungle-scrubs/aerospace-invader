import Foundation

// MARK: - Aerospace Command Execution

/// Abstraction over the AeroSpace CLI for testability.
/// Production code uses `AerospaceAPI`; tests can inject a mock.
public protocol AerospaceCommandExecutor {
    /// Whether the aerospace binary is installed on this system.
    var isInstalled: Bool { get }

    /// Ensure aerospace is running, enabling it if necessary.
    /// - Returns: Success or a typed `AerospaceError`.
    func ensureEnabled() -> Result<Void, AerospaceError>

    /// Fetch all non-empty workspaces and the currently focused one.
    /// - Returns: Tuple of workspace names and the focused workspace (if any).
    func getWorkspacesWithFocus() -> (workspaces: [String], focused: String?)

    /// Get only the list of non-empty workspace names.
    /// - Returns: Array of workspace name strings.
    func getNonEmptyWorkspaces() -> [String]

    /// Get the name of the currently focused workspace.
    /// - Returns: Workspace name, or nil if unavailable.
    func getCurrentWorkspace() -> String?

    /// Switch to a workspace by name (fire-and-forget).
    /// - Parameter workspace: The workspace name to switch to.
    func switchToWorkspace(_ workspace: String)

    /// Toggle between current and previous workspace (fire-and-forget).
    func workspaceBackAndForth()

    /// Get keybindings for an AeroSpace mode.
    /// - Parameter mode: The mode name (e.g. "service", "resize").
    /// - Returns: Dictionary of key → command, or nil on failure.
    func getBindings(mode: String) -> [String: String]?

    /// Get the name of the currently active AeroSpace mode.
    /// - Returns: Mode name (e.g. "main"), or nil on failure.
    func getCurrentMode() -> String?
}

// MARK: - Workspace Order Persistence

/// Abstraction over workspace order file persistence.
/// Production code uses `OrderManager`; tests can inject a mock.
public protocol WorkspaceOrderProvider {
    /// Save a workspace order to disk.
    /// - Parameter order: Array of workspace names to persist.
    func saveOrder(_ order: [String])

    /// Reconcile the saved order with the currently active workspaces, persist the result, and return it.
    /// Preserves custom ordering, removes closed workspaces, appends new ones — then saves in one step.
    /// - Parameter current: The current list of non-empty workspaces.
    /// - Returns: The merged, now-persisted workspace order.
    func reconcile(with current: [String]) -> [String]
}

// MARK: - Configuration

/// Abstraction over hotkey configuration.
/// Production code uses `ConfigManager`; tests can inject a mock.
public protocol ConfigurationProvider {
    /// The current hotkey configuration.
    var config: Config { get }
}
