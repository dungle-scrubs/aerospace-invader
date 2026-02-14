@testable import AerospaceInvaderCore
import Foundation

// MARK: - Mock AerospaceCommandExecutor

/// Mock implementation of `AerospaceCommandExecutor` for unit testing.
/// Records all calls for assertion and returns configurable values.
final class MockAerospaceAPI: AerospaceCommandExecutor {
    var isInstalled: Bool = true

    var ensureEnabledResult: Result<Void, AerospaceError> = .success(())
    var workspacesWithFocus: (workspaces: [String], focused: String?) = ([], nil)
    var currentMode: String? = "main"
    var bindings: [String: String]? = nil

    /// Records every workspace switch request.
    var switchedWorkspaces: [String] = []
    /// Number of times `workspaceBackAndForth` was called.
    var backAndForthCallCount = 0

    func ensureEnabled() -> Result<Void, AerospaceError> {
        ensureEnabledResult
    }

    func getWorkspacesWithFocus() -> (workspaces: [String], focused: String?) {
        workspacesWithFocus
    }

    func getNonEmptyWorkspaces() -> [String] {
        workspacesWithFocus.workspaces
    }

    func getCurrentWorkspace() -> String? {
        workspacesWithFocus.focused
    }

    func switchToWorkspace(_ workspace: String) {
        switchedWorkspaces.append(workspace)
        // Simulate AeroSpace actually switching
        workspacesWithFocus.focused = workspace
    }

    func workspaceBackAndForth() {
        backAndForthCallCount += 1
    }

    func getBindings(mode: String) -> [String: String]? {
        bindings
    }

    func getCurrentMode() -> String? {
        currentMode
    }
}

// MARK: - Mock WorkspaceOrderProvider

/// Mock implementation of `WorkspaceOrderProvider` for unit testing.
/// Uses an in-memory array instead of file I/O.
final class MockOrderProvider: WorkspaceOrderProvider {
    var savedOrder: [String] = []
    var saveCount = 0

    func loadOrder() -> [String] {
        savedOrder
    }

    func saveOrder(_ order: [String]) {
        savedOrder = order
        saveCount += 1
    }

    func mergeWithCurrent(_ current: [String]) -> [String] {
        OrderManager.merge(saved: savedOrder, current: current)
    }
}

// MARK: - Mock ConfigurationProvider

/// Mock implementation of `ConfigurationProvider` for unit testing.
final class MockConfigProvider: ConfigurationProvider {
    var config: Config = .default
}
