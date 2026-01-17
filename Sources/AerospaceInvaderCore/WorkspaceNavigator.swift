import Foundation

public class WorkspaceNavigator {
    public static let shared = WorkspaceNavigator()

    // Serial queue for thread-safe state access
    private let stateQueue = DispatchQueue(label: "com.aerospace-invader.navigator-state")

    // State protected by stateQueue
    private var _cachedWorkspaces: [String] = []
    private var _cachedFocused: String?
    private var _cachedOrder: [String] = []
    private var _previousWorkspace: String?

    private init() {}

    // MARK: - Thread-safe state accessors

    private func withState<T>(_ block: () -> T) -> T {
        stateQueue.sync { block() }
    }

    private func mutateState(_ block: () -> Void) {
        stateQueue.sync { block() }
    }

    /// Get current index in ordered list
    private func getCurrentIndex(in order: [String], current: String?) -> Int {
        guard let ws = current, let idx = order.firstIndex(of: ws) else { return 0 }
        return idx
    }

    /// Detect if user manually switched workspaces via AeroSpace keybinds (opt+letter)
    /// Call this BEFORE any navigation to track manual switches in history
    private func detectManualSwitch() {
        // Get actual current workspace from AeroSpace (blocking call - do outside queue)
        let actualCurrent = AerospaceAPI.getCurrentWorkspace()

        mutateState {
            guard let actual = actualCurrent,
                  actual != _cachedFocused,
                  !_cachedOrder.isEmpty else { return }

            // User switched manually - update tracking
            if _cachedFocused != nil {
                _previousWorkspace = _cachedFocused
            }
            _cachedFocused = actual
        }
    }

    /// Refresh cache from aerospace - must be called from stateQueue or with lock held
    private func _refreshCacheUnsafe() {
        let (workspaces, focused) = AerospaceAPI.getWorkspacesWithFocus()
        let order = OrderManager.shared.mergeWithCurrent(workspaces)
        OrderManager.shared.saveOrder(order)

        // Track previous workspace when focus changes
        if let newFocused = focused, newFocused != _cachedFocused, _cachedFocused != nil {
            _previousWorkspace = _cachedFocused
        }

        _cachedWorkspaces = workspaces
        _cachedFocused = focused
        _cachedOrder = order
    }

    /// Public refresh - thread-safe
    public func refreshCache() {
        mutateState { _refreshCacheUnsafe() }
    }

    /// Navigate backward - uses cache for instant response, refreshes after
    public func back(completion: @escaping ([String], String?) -> Void) {
        // Detect manual switches before navigation
        detectManualSwitch()

        // Capture state and perform navigation atomically
        let (shouldNavigate, order, target, cacheWasEmpty) = withState { () -> (Bool, [String], String?, Bool) in
            let wasEmpty = _cachedOrder.isEmpty

            guard !_cachedOrder.isEmpty else {
                return (false, [], nil, wasEmpty)
            }

            let idx = getCurrentIndex(in: _cachedOrder, current: _cachedFocused)
            let newIdx = idx > 0 ? idx - 1 : _cachedOrder.count - 1
            let target = _cachedOrder[newIdx]
            _previousWorkspace = _cachedFocused
            _cachedFocused = target

            return (true, _cachedOrder, target, wasEmpty)
        }

        if shouldNavigate, let target = target {
            AerospaceAPI.switchToWorkspace(target)
            completion(order, target)
        }

        // Refresh cache in background for next time
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if cacheWasEmpty {
                // Cache was empty - refresh and navigate
                let (order, target) = self.withState { () -> ([String], String?) in
                    self._refreshCacheUnsafe()
                    guard !self._cachedOrder.isEmpty else { return ([], nil) }

                    let idx = self.getCurrentIndex(in: self._cachedOrder, current: self._cachedFocused)
                    let newIdx = idx > 0 ? idx - 1 : self._cachedOrder.count - 1
                    let target = self._cachedOrder[newIdx]
                    self._cachedFocused = target
                    return (self._cachedOrder, target)
                }

                if let target = target {
                    AerospaceAPI.switchToWorkspace(target)
                    DispatchQueue.main.async { completion(order, target) }
                }
            } else {
                // Just refresh for next time
                self.refreshCache()
            }
        }
    }

    /// Navigate forward - uses cache for instant response, refreshes after
    public func forward(completion: @escaping ([String], String?) -> Void) {
        // Detect manual switches before navigation
        detectManualSwitch()

        // Capture state and perform navigation atomically
        let (shouldNavigate, order, target, cacheWasEmpty) = withState { () -> (Bool, [String], String?, Bool) in
            let wasEmpty = _cachedOrder.isEmpty

            guard !_cachedOrder.isEmpty else {
                return (false, [], nil, wasEmpty)
            }

            let idx = getCurrentIndex(in: _cachedOrder, current: _cachedFocused)
            let newIdx = idx < _cachedOrder.count - 1 ? idx + 1 : 0
            let target = _cachedOrder[newIdx]
            _previousWorkspace = _cachedFocused
            _cachedFocused = target

            return (true, _cachedOrder, target, wasEmpty)
        }

        if shouldNavigate, let target = target {
            AerospaceAPI.switchToWorkspace(target)
            completion(order, target)
        }

        // Refresh cache in background for next time
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if cacheWasEmpty {
                // Cache was empty - refresh and navigate
                let (order, target) = self.withState { () -> ([String], String?) in
                    self._refreshCacheUnsafe()
                    guard !self._cachedOrder.isEmpty else { return ([], nil) }

                    let idx = self.getCurrentIndex(in: self._cachedOrder, current: self._cachedFocused)
                    let newIdx = idx < self._cachedOrder.count - 1 ? idx + 1 : 0
                    let target = self._cachedOrder[newIdx]
                    self._cachedFocused = target
                    return (self._cachedOrder, target)
                }

                if let target = target {
                    AerospaceAPI.switchToWorkspace(target)
                    DispatchQueue.main.async { completion(order, target) }
                }
            } else {
                // Just refresh for next time
                self.refreshCache()
            }
        }
    }

    /// Toggle between current and previous workspace - uses cache for instant response
    public func toggle(completion: @escaping ([String], String?) -> Void) {
        // Detect manual switches before toggle
        detectManualSwitch()

        // Capture state and perform toggle atomically
        let (shouldToggle, order, target, cacheWasEmpty) = withState { () -> (Bool, [String], String?, Bool) in
            let wasEmpty = _cachedOrder.isEmpty

            guard !_cachedOrder.isEmpty,
                  let prev = _previousWorkspace,
                  _cachedOrder.contains(prev) else {
                return (false, _cachedOrder, nil, wasEmpty)
            }

            let oldFocused = _cachedFocused
            _previousWorkspace = oldFocused
            _cachedFocused = prev

            return (true, _cachedOrder, prev, wasEmpty)
        }

        if shouldToggle, let target = target {
            AerospaceAPI.switchToWorkspace(target)
            completion(order, target)
        }

        // Refresh cache in background (but don't do manual switch detection -
        // we just initiated a switch ourselves, detecting it would undo our toggle)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if cacheWasEmpty {
                // Cache was empty - need to refresh and then toggle
                let (order, target) = self.withState { () -> ([String], String?) in
                    self._refreshCacheUnsafe()

                    guard let prev = self._previousWorkspace,
                          self._cachedOrder.contains(prev) else {
                        return ([], nil)
                    }

                    let oldFocused = self._cachedFocused
                    self._previousWorkspace = oldFocused
                    self._cachedFocused = prev

                    return (self._cachedOrder, prev)
                }

                if let target = target {
                    AerospaceAPI.switchToWorkspace(target)
                    DispatchQueue.main.async { completion(order, target) }
                }
            }
            // If cache was populated, we already toggled - just let refreshCache
            // happen naturally on next back/forward to avoid racing with our switch
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

    // MARK: - Testing support

    /// Reset state for testing
    internal func resetForTesting() {
        mutateState {
            _cachedWorkspaces = []
            _cachedFocused = nil
            _cachedOrder = []
            _previousWorkspace = nil
        }
    }

    /// Set state directly for testing
    internal func setStateForTesting(order: [String], focused: String?, previous: String?) {
        mutateState {
            _cachedOrder = order
            _cachedWorkspaces = order
            _cachedFocused = focused
            _previousWorkspace = previous
        }
    }

    /// Get current state for testing assertions
    internal func getStateForTesting() -> (order: [String], focused: String?, previous: String?) {
        withState { (_cachedOrder, _cachedFocused, _previousWorkspace) }
    }
}
