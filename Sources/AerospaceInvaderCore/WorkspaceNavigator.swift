import Foundation

public class WorkspaceNavigator {
    public static let shared = WorkspaceNavigator()

    // Cache for instant response
    private var cachedWorkspaces: [String] = []
    private var cachedFocused: String?
    private var cachedOrder: [String] = []
    private var previousWorkspace: String?

    private init() {}

    /// Get current index in ordered list
    private func getCurrentIndex(in order: [String], current: String?) -> Int {
        guard let ws = current, let idx = order.firstIndex(of: ws) else { return 0 }
        return idx
    }

    /// Refresh cache from aerospace (call on background thread)
    public func refreshCache() {
        let (workspaces, focused) = AerospaceAPI.getWorkspacesWithFocus()
        let order = OrderManager.shared.mergeWithCurrent(workspaces)
        OrderManager.shared.saveOrder(order)

        // Track previous workspace when focus changes
        if let newFocused = focused, newFocused != cachedFocused, cachedFocused != nil {
            previousWorkspace = cachedFocused
        }

        cachedWorkspaces = workspaces
        cachedFocused = focused
        cachedOrder = order
    }

    /// Navigate backward - uses cache for instant response, refreshes after
    public func back(completion: @escaping ([String], String?) -> Void) {
        let cacheWasEmpty = cachedOrder.isEmpty

        // Use cache for instant navigation
        if !cachedOrder.isEmpty {
            let idx = getCurrentIndex(in: cachedOrder, current: cachedFocused)
            let newIdx = idx > 0 ? idx - 1 : cachedOrder.count - 1
            let target = cachedOrder[newIdx]
            previousWorkspace = cachedFocused
            cachedFocused = target
            AerospaceAPI.switchToWorkspace(target)
            completion(cachedOrder, target)
        }

        // Refresh cache in background for next time (only navigate if cache was empty)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.refreshCache()
            if cacheWasEmpty {
                DispatchQueue.main.async {
                    guard let self = self, !self.cachedOrder.isEmpty else { return }
                    let idx = self.getCurrentIndex(in: self.cachedOrder, current: self.cachedFocused)
                    let newIdx = idx > 0 ? idx - 1 : self.cachedOrder.count - 1
                    let target = self.cachedOrder[newIdx]
                    self.cachedFocused = target
                    AerospaceAPI.switchToWorkspace(target)
                    completion(self.cachedOrder, target)
                }
            }
        }
    }

    /// Navigate forward - uses cache for instant response, refreshes after
    public func forward(completion: @escaping ([String], String?) -> Void) {
        let cacheWasEmpty = cachedOrder.isEmpty

        // Use cache for instant navigation
        if !cachedOrder.isEmpty {
            let idx = getCurrentIndex(in: cachedOrder, current: cachedFocused)
            let newIdx = idx < cachedOrder.count - 1 ? idx + 1 : 0
            let target = cachedOrder[newIdx]
            previousWorkspace = cachedFocused
            cachedFocused = target
            AerospaceAPI.switchToWorkspace(target)
            completion(cachedOrder, target)
        }

        // Refresh cache in background for next time (only navigate if cache was empty)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.refreshCache()
            if cacheWasEmpty {
                DispatchQueue.main.async {
                    guard let self = self, !self.cachedOrder.isEmpty else { return }
                    let idx = self.getCurrentIndex(in: self.cachedOrder, current: self.cachedFocused)
                    let newIdx = idx < self.cachedOrder.count - 1 ? idx + 1 : 0
                    let target = self.cachedOrder[newIdx]
                    self.cachedFocused = target
                    AerospaceAPI.switchToWorkspace(target)
                    completion(self.cachedOrder, target)
                }
            }
        }
    }

    /// Toggle between current and previous workspace - uses cache for instant response
    public func toggle(completion: @escaping ([String], String?) -> Void) {
        let cacheWasEmpty = cachedOrder.isEmpty

        // Use cache for instant toggle
        if !cachedOrder.isEmpty, let prev = previousWorkspace, cachedOrder.contains(prev) {
            let oldFocused = cachedFocused
            previousWorkspace = oldFocused
            cachedFocused = prev
            AerospaceAPI.switchToWorkspace(prev)
            completion(cachedOrder, prev)
        }

        // Refresh cache in background (only toggle if cache was empty)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.refreshCache()
            if cacheWasEmpty {
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let prev = self.previousWorkspace, self.cachedOrder.contains(prev) {
                        let oldFocused = self.cachedFocused
                        self.previousWorkspace = oldFocused
                        self.cachedFocused = prev
                        AerospaceAPI.switchToWorkspace(prev)
                        completion(self.cachedOrder, prev)
                    }
                }
            }
        }
    }

    /// Synchronous versions for backward compatibility
    public func back() -> (order: [String], current: String?) {
        let (nonEmpty, current) = AerospaceAPI.getWorkspacesWithFocus()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx > 0 ? idx - 1 : order.count - 1
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }

    public func forward() -> (order: [String], current: String?) {
        let (nonEmpty, current) = AerospaceAPI.getWorkspacesWithFocus()
        let order = OrderManager.shared.mergeWithCurrent(nonEmpty)
        OrderManager.shared.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = idx < order.count - 1 ? idx + 1 : 0
        let target = order[newIdx]

        AerospaceAPI.switchToWorkspace(target)
        return (order, target)
    }
}
