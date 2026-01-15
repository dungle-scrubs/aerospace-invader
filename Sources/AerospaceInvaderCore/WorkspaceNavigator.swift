import Foundation

public class WorkspaceNavigator {
    public static let shared = WorkspaceNavigator()

    private init() {}

    /// Get current index in ordered list
    private func getCurrentIndex(in order: [String], current: String?) -> Int {
        guard let ws = current, let idx = order.firstIndex(of: ws) else { return 0 }
        return idx
    }

    /// Navigate backward
    public func back() -> (order: [String], current: String?) {
        let nonEmpty = AerospaceAPI.getNonEmptyWorkspaces()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let current = AerospaceAPI.getCurrentWorkspace()
        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx > 0 ? idx - 1 : order.count - 1
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }

    /// Navigate forward
    public func forward() -> (order: [String], current: String?) {
        let nonEmpty = AerospaceAPI.getNonEmptyWorkspaces()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let current = AerospaceAPI.getCurrentWorkspace()
        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx < order.count - 1 ? idx + 1 : 0
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }
}
