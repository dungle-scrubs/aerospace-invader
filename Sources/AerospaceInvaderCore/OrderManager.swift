import Foundation

/// Persists the user's custom workspace ordering to `~/.config/aerospace-invader/order.json`.
/// Thread-safe via a serial dispatch queue.
public final class OrderManager: WorkspaceOrderProvider {
    /// Shared singleton for production use.
    public static let shared = OrderManager()

    private let queue = DispatchQueue(label: "com.aerospace-invader.order")
    private let orderFile: String

    private init() {
        orderFile = ConfigStore.orderFile
        ConfigStore.ensureDirectory(context: "OrderManager")
    }

    /// Creates an order manager backed by a specific file (for testing).
    /// - Parameter orderFile: Absolute path to the order JSON file.
    init(orderFile: String) {
        self.orderFile = orderFile
    }

    /// Loads the saved workspace order from disk (thread-safe).
    /// - Returns: Array of workspace names, or empty if no file or parse error.
    private func loadOrder() -> [String] {
        queue.sync {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: orderFile))
                return try JSONDecoder().decode([String].self, from: data)
            } catch {
                // File-not-found is expected on first run — only log actual errors
                if !ConfigStore.isFileNotFound(error) {
                    fputs("OrderManager: failed to load order — \(error.localizedDescription)\n", stderr)
                }
                return []
            }
        }
    }

    /// Saves a workspace order to disk (thread-safe, async write).
    /// - Parameter order: Array of workspace names to persist.
    public func saveOrder(_ order: [String]) {
        queue.async {
            do {
                let data = try JSONEncoder().encode(order)
                try data.write(to: URL(fileURLWithPath: self.orderFile))
            } catch {
                fputs("OrderManager: failed to save order — \(error.localizedDescription)\n", stderr)
            }
        }
    }

    /// Reconciles saved order with the currently active workspaces and persists the result.
    /// Preserves custom ordering, removes closed workspaces, appends new ones, then saves.
    /// - Parameter current: The current list of non-empty workspaces from AeroSpace.
    /// - Returns: The merged, now-persisted workspace order.
    public func reconcile(with current: [String]) -> [String] {
        let order = OrderManager.merge(saved: loadOrder(), current: current)
        saveOrder(order)
        return order
    }

    /// Pure merge function — testable without file I/O.
    /// Keeps saved items that still exist (deduplicated), then appends new ones.
    /// - Parameters:
    ///   - saved: Previously saved workspace order.
    ///   - current: Currently active workspaces from AeroSpace.
    /// - Returns: Merged order preserving custom arrangement.
    public static func merge(saved: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        var seen = Set<String>()
        var result: [String] = []

        for ws in saved {
            if currentSet.contains(ws) && !seen.contains(ws) {
                result.append(ws)
                seen.insert(ws)
            }
        }

        for ws in current where !seen.contains(ws) {
            result.append(ws)
            seen.insert(ws)
        }

        return result
    }
}
