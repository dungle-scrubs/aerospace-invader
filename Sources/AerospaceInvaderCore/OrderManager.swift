import Foundation

/// Persists the user's custom workspace ordering. Now a thin adapter over `PersistedState`,
/// which owns the queue, atomic writes, and directory. Pure merge logic forwards to
/// PersistedState so the file seam has one owner.
public final class OrderManager: WorkspaceOrderProvider {
    /// Shared singleton for production use.
    public static let shared = OrderManager()

    private let persisted: PersistedState

    private init() {
        persisted = PersistedState.shared
    }

    /// Creates an order manager backed by a specific file (for testing).
    /// - Parameter orderFile: Absolute path to the order JSON file.
    init(orderFile: String) {
        persisted = PersistedState(orderFile: orderFile)
    }

    /// Test initializer that injects an explicit persisted state.
    init(persisted: PersistedState) {
        self.persisted = persisted
    }

    /// Loads the saved workspace order from disk (thread-safe).
    private func loadOrder() -> [String] {
        persisted.loadOrder()
    }

    /// Saves a workspace order to disk (thread-safe, barrier-atomic).
    public func saveOrder(_ order: [String]) {
        persisted.saveOrder(order)
    }

    /// Reconciles saved order with the currently active workspaces and persists the result.
    public func reconcile(with current: [String]) -> [String] {
        persisted.reconcile(with: current)
    }

    /// Pure merge function — forwards to `PersistedState` so there is one implementation.
    public static func merge(saved: [String], current: [String]) -> [String] {
        PersistedState.merge(saved: saved, current: current)
    }
}
