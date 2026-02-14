import Foundation

/// Handles workspace navigation with cache-first response for instant feedback.
/// Keeps an ordered list of workspaces in sync with AeroSpace and `OrderManager`.
/// All state mutations are serialized on an internal queue for thread safety.
public class WorkspaceNavigator {
    /// Shared singleton using default dependencies.
    public static let shared = WorkspaceNavigator()

    private let api: AerospaceCommandExecutor
    private let orderProvider: WorkspaceOrderProvider

    /// Serial queue for thread-safe state access.
    private let stateQueue = DispatchQueue(label: "com.aerospace-invader.navigator-state")

    // State protected by stateQueue
    private var _cachedFocused: String?
    private var _cachedOrder: [String] = []
    private var _previousWorkspace: String?

    /// Creates a navigator with injected dependencies.
    /// - Parameters:
    ///   - api: The aerospace command executor (default: `AerospaceAPI.shared`).
    ///   - orderProvider: The workspace order provider (default: `OrderManager.shared`).
    public init(api: AerospaceCommandExecutor = AerospaceAPI.shared,
                orderProvider: WorkspaceOrderProvider = OrderManager.shared) {
        self.api = api
        self.orderProvider = orderProvider
    }

    // MARK: - Thread-safe State Accessors

    private func withState<T>(_ block: () -> T) -> T {
        stateQueue.sync { block() }
    }

    private func mutateState(_ block: () -> Void) {
        stateQueue.sync { block() }
    }

    /// Get current index of a workspace in an ordered list.
    /// - Parameters:
    ///   - order: The workspace order to search.
    ///   - current: The workspace name to find.
    /// - Returns: Index of the workspace, or 0 if not found.
    private func getCurrentIndex(in order: [String], current: String?) -> Int {
        guard let ws = current, let idx = order.firstIndex(of: ws) else { return 0 }
        return idx
    }

    // MARK: - Manual Switch Detection

    /// Detects if the user manually switched workspaces via AeroSpace keybinds.
    /// Must be called BEFORE navigation to keep history accurate.
    private func detectManualSwitch() {
        let actualCurrent = api.getCurrentWorkspace()

        mutateState {
            guard let actual = actualCurrent,
                  actual != _cachedFocused,
                  !_cachedOrder.isEmpty else { return }

            if _cachedFocused != nil {
                _previousWorkspace = _cachedFocused
            }
            _cachedFocused = actual
        }
    }

    // MARK: - Cache

    /// Refreshes the workspace cache from AeroSpace — must be called within `stateQueue`.
    private func _refreshCacheUnsafe() {
        let (workspaces, focused) = api.getWorkspacesWithFocus()
        let order = orderProvider.mergeWithCurrent(workspaces)
        orderProvider.saveOrder(order)

        if let newFocused = focused, newFocused != _cachedFocused, _cachedFocused != nil {
            _previousWorkspace = _cachedFocused
        }

        _cachedFocused = focused
        _cachedOrder = order
    }

    /// Thread-safe cache refresh.
    public func refreshCache() {
        mutateState { _refreshCacheUnsafe() }
    }

    // MARK: - Navigation

    /// Direction for workspace cycling.
    private enum Direction {
        case backward
        case forward

        /// Computes the next index in a circular list.
        /// - Parameters:
        ///   - current: Current index.
        ///   - count: Total number of items.
        /// - Returns: Next index, wrapping around.
        func nextIndex(from current: Int, count: Int) -> Int {
            guard count > 0 else { return 0 }
            switch self {
            case .backward:
                return current > 0 ? current - 1 : count - 1
            case .forward:
                return current < count - 1 ? current + 1 : 0
            }
        }
    }

    /// Core navigation logic shared by `back()` and `forward()`.
    /// Uses cache for instant response, refreshes in background for next time.
    /// - Parameters:
    ///   - direction: Which direction to navigate.
    ///   - completion: Called with the ordered workspaces and the new current workspace.
    private func navigate(_ direction: Direction, completion: @escaping ([String], String?) -> Void) {
        detectManualSwitch()

        let (shouldNavigate, order, target, cacheWasEmpty) = withState { () -> (Bool, [String], String?, Bool) in
            let wasEmpty = _cachedOrder.isEmpty

            guard !_cachedOrder.isEmpty else {
                return (false, [], nil, wasEmpty)
            }

            let idx = getCurrentIndex(in: _cachedOrder, current: _cachedFocused)
            let newIdx = direction.nextIndex(from: idx, count: _cachedOrder.count)
            guard newIdx < _cachedOrder.count else { return (false, _cachedOrder, nil, wasEmpty) }
            let target = _cachedOrder[newIdx]
            _previousWorkspace = _cachedFocused
            _cachedFocused = target

            return (true, _cachedOrder, target, wasEmpty)
        }

        if shouldNavigate, let target = target {
            api.switchToWorkspace(target)
            completion(order, target)
        }

        // Refresh cache in background for next navigation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if cacheWasEmpty {
                let (order, target) = self.withState { () -> ([String], String?) in
                    self._refreshCacheUnsafe()
                    guard !self._cachedOrder.isEmpty else { return ([], nil) }

                    let idx = self.getCurrentIndex(in: self._cachedOrder, current: self._cachedFocused)
                    let newIdx = direction.nextIndex(from: idx, count: self._cachedOrder.count)
                    guard newIdx < self._cachedOrder.count else { return (self._cachedOrder, nil) }
                    let target = self._cachedOrder[newIdx]
                    self._cachedFocused = target
                    return (self._cachedOrder, target)
                }

                if let target = target {
                    self.api.switchToWorkspace(target)
                    DispatchQueue.main.async { completion(order, target) }
                }
            } else {
                self.refreshCache()
            }
        }
    }

    /// Navigate to the previous workspace (wraps around).
    /// - Parameter completion: Called with the ordered workspaces and new current workspace.
    public func back(completion: @escaping ([String], String?) -> Void) {
        navigate(.backward, completion: completion)
    }

    /// Navigate to the next workspace (wraps around).
    /// - Parameter completion: Called with the ordered workspaces and new current workspace.
    public func forward(completion: @escaping ([String], String?) -> Void) {
        navigate(.forward, completion: completion)
    }

    /// Toggle between current and previous workspace using AeroSpace's native command.
    /// - Parameter completion: Called with the ordered workspaces and current workspace after toggle.
    public func toggle(completion: @escaping ([String], String?) -> Void) {
        api.workspaceBackAndForth()

        // Brief delay to let AeroSpace complete the switch, then update UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let (workspaces, current) = self.api.getWorkspacesWithFocus()
            let order = self.orderProvider.mergeWithCurrent(workspaces)
            self.orderProvider.saveOrder(order)

            self.mutateState {
                self._cachedOrder = order
                self._cachedFocused = current
            }

            completion(order, current)
        }
    }

    /// Synchronous backward navigation (blocking — fetches fresh state from AeroSpace).
    /// - Returns: Tuple of ordered workspaces and the new current workspace.
    public func back() -> (order: [String], current: String?) {
        navigateSync(.backward)
    }

    /// Synchronous forward navigation (blocking — fetches fresh state from AeroSpace).
    /// - Returns: Tuple of ordered workspaces and the new current workspace.
    public func forward() -> (order: [String], current: String?) {
        navigateSync(.forward)
    }

    /// Core sync navigation — shared by `back()` and `forward()`.
    private func navigateSync(_ direction: Direction) -> (order: [String], current: String?) {
        let (nonEmpty, current) = api.getWorkspacesWithFocus()
        let order = orderProvider.mergeWithCurrent(nonEmpty)
        orderProvider.saveOrder(order)

        guard !order.isEmpty else { return ([], nil) }

        let idx = getCurrentIndex(in: order, current: current)
        let newIdx = direction.nextIndex(from: idx, count: order.count)
        guard newIdx < order.count else { return (order, nil) }
        let target = order[newIdx]

        api.switchToWorkspace(target)
        return (order, target)
    }

    // MARK: - Testing Support

    /// Reset all cached state. For testing only.
    internal func resetForTesting() {
        mutateState {
            _cachedFocused = nil
            _cachedOrder = []
            _previousWorkspace = nil
        }
    }

    /// Set state directly for testing.
    /// - Parameters:
    ///   - order: Workspace order to set.
    ///   - focused: Currently focused workspace.
    ///   - previous: Previously focused workspace.
    internal func setStateForTesting(order: [String], focused: String?, previous: String?) {
        mutateState {
            _cachedOrder = order
            _cachedFocused = focused
            _previousWorkspace = previous
        }
    }

    /// Get current state for testing assertions.
    /// - Returns: Tuple of order, focused workspace, and previous workspace.
    internal func getStateForTesting() -> (order: [String], focused: String?, previous: String?) {
        withState { (_cachedOrder, _cachedFocused, _previousWorkspace) }
    }
}
