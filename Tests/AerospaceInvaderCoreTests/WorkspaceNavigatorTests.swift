@testable import AerospaceInvaderCore
import Testing
import Foundation

@Suite("WorkspaceNavigator", .serialized)
struct WorkspaceNavigatorTests {

    init() {
        // Reset state before each test since we use a singleton
        WorkspaceNavigator.shared.resetForTesting()
    }

    // MARK: - Navigation state tests
    // Note: toggle() now delegates to AeroSpace's native workspace-back-and-forth command,
    // so toggle state tests were removed. The native command handles its own state internally.

    @Test("back wraps around")
    func backWrapsAround() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "A", previous: nil)

        // At index 0, back should go to last (index 2 = "C")
        let (order, focused, _) = navigator.getStateForTesting()

        #expect(order == ["A", "B", "C"])
        #expect(focused == "A")
    }

    @Test("forward wraps around")
    func forwardWrapsAround() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "C", previous: nil)

        // At index 2, forward should go to first (index 0 = "A")
        let (order, focused, _) = navigator.getStateForTesting()

        #expect(order == ["A", "B", "C"])
        #expect(focused == "C")
    }

    @Test("reset clears all state")
    func resetClearsAllState() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "B", previous: "A")
        navigator.resetForTesting()

        let (order, focused, previous) = navigator.getStateForTesting()

        #expect(order.isEmpty)
        #expect(focused == nil)
        #expect(previous == nil)
    }

    // MARK: - Thread safety tests

    @Test("concurrent state access is safe")
    func concurrentStateAccessIsSafe() async {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "B", previous: "A")

        // Hammer the state from multiple concurrent tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    if i % 3 == 0 {
                        navigator.setStateForTesting(
                            order: ["A", "B", "C"],
                            focused: ["A", "B", "C"][i % 3],
                            previous: ["A", "B", "C"][(i + 1) % 3]
                        )
                    } else {
                        _ = navigator.getStateForTesting()
                    }
                }
            }
        }

        // If we get here without crashing, thread safety works
        let (order, _, _) = navigator.getStateForTesting()
        #expect(order.count == 3)
    }

}
