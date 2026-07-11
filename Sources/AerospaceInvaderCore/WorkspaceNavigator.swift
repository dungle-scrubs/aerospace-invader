import Foundation

/// Handles workspace navigation with cache-first response for instant feedback.
/// Keeps an ordered list of workspaces in sync with AeroSpace and `OrderManager`.
/// All state mutations are serialized on an internal queue for thread safety.
public final class WorkspaceNavigator {
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

    /// Computes the navigation target for a direction from an ordered list and current focus.
    /// From an unknown or absent focus, forward starts at the first workspace and backward at
    /// the last — rather than treating "not found" as index 0, which would skip the first.
    /// - Returns: The target workspace name, or nil if the order is empty.
    private func computeTarget(in order: [String], focused: String?, direction: Direction) -> String? {
        guard !order.isEmpty else { return nil }
        guard let ws = focused, let idx = order.firstIndex(of: ws) else {
            return direction == .forward ? order.first : order.last
        }
        return order[direction.nextIndex(from: idx, count: order.count)]
    }

    // MARK: - Cache

    /// Refreshes the workspace cache from AeroSpace. Safe to call from any thread; the blocking
    /// CLI query and file reconciliation run OUTSIDE the state lock, which is taken only to
    /// publish the results — so a concurrent cached read never blocks on external I/O.
    public func refreshCache() {
        let (workspaces, focused) = api.getWorkspacesWithFocus()
        let order = orderProvider.reconcile(with: workspaces)

        mutateState {
            // Adopt a focus change made outside this app (e.g. AeroSpace's own keybinds), but
            // ignore a reading equal to the workspace we just navigated away from: that is the
            // signature of a fire-and-forget switch that hasn't landed yet, and adopting it would
            // revert the optimistic focus during rapid navigation. A nil reading (transient CLI
            // failure) is left alone rather than wiping the known focus.
            if let newFocused = focused,
               newFocused != _cachedFocused,
               newFocused != _previousWorkspace {
                if _cachedFocused != nil {
                    _previousWorkspace = _cachedFocused
                }
                _cachedFocused = newFocused
            }
            _cachedOrder = order
        }
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
    /// Serves the response from cache for instant feedback WITHOUT launching a process on the
    /// calling thread, then reconciles state in the background for the next navigation.
    /// - Parameters:
    ///   - direction: Which direction to navigate.
    ///   - completion: Called with the ordered workspaces and the new current workspace.
    private func navigate(_ direction: Direction, completion: @escaping ([String], String?) -> Void) {
        let (order, target) = withState { () -> ([String], String?) in
            guard let target = computeTarget(in: _cachedOrder, focused: _cachedFocused, direction: direction) else {
                return (_cachedOrder, nil)
            }
            _previousWorkspace = _cachedFocused
            _cachedFocused = target
            return (_cachedOrder, target)
        }

        if let target = target {
            // Cache hit: respond instantly, then refresh in the background after a short settle
            // so the re-read reflects our just-issued switch instead of racing it.
            api.switchToWorkspace(target)
            completion(order, target)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.refreshCache()
            }
        } else {
            // Cold start (empty cache): populate from AeroSpace off the main thread, then navigate.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.refreshCache()
                let (order, target) = self.withState { () -> ([String], String?) in
                    guard let target = self.computeTarget(in: self._cachedOrder, focused: self._cachedFocused, direction: direction) else {
                        return (self._cachedOrder, nil)
                    }
                    self._previousWorkspace = self._cachedFocused
                    self._cachedFocused = target
                    return (self._cachedOrder, target)
                }
                if let target = target {
                    self.api.switchToWorkspace(target)
                    DispatchQueue.main.async { completion(order, target) }
                }
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

        // Brief delay to let AeroSpace complete the switch, then read fresh state on a
        // background queue (the CLI query blocks) and deliver the UI update on main.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            let (workspaces, current) = self.api.getWorkspacesWithFocus()
            let order = self.orderProvider.reconcile(with: workspaces)

            self.mutateState {
                self._cachedOrder = order
                self._cachedFocused = current
            }

            DispatchQueue.main.async { completion(order, current) }
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
        let order = orderProvider.reconcile(with: nonEmpty)

        guard let target = computeTarget(in: order, focused: current, direction: direction) else {
            return (order, nil)
        }

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
