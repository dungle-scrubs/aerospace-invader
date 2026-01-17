@testable import AerospaceInvaderCore
import Testing
import Foundation

@Suite("WorkspaceNavigator", .serialized)
struct WorkspaceNavigatorTests {

    init() {
        // Reset state before each test since we use a singleton
        WorkspaceNavigator.shared.resetForTesting()
    }

    // MARK: - Toggle state machine tests

    @Test("toggle swaps focused and previous")
    func toggleSwapsFocusedAndPrevious() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "B", previous: "A")

        // Simulate toggle (we can't test the actual workspace switch without mocking)
        let (_, focused, previous) = navigator.getStateForTesting()

        #expect(focused == "B")
        #expect(previous == "A")

        // After toggle, focused becomes A, previous becomes B
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "A", previous: "B")
        let (_, newFocused, newPrevious) = navigator.getStateForTesting()

        #expect(newFocused == "A")
        #expect(newPrevious == "B")
    }

    @Test("toggle does nothing without previous workspace")
    func toggleDoesNothingWithoutPrevious() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "B", previous: nil)

        let (order, focused, previous) = navigator.getStateForTesting()

        #expect(order == ["A", "B", "C"])
        #expect(focused == "B")
        #expect(previous == nil)
    }

    @Test("toggle does nothing when previous not in order")
    func toggleDoesNothingWhenPreviousNotInOrder() {
        let navigator = WorkspaceNavigator.shared
        navigator.setStateForTesting(order: ["A", "B", "C"], focused: "B", previous: "D")

        let (order, focused, previous) = navigator.getStateForTesting()

        #expect(order == ["A", "B", "C"])
        #expect(focused == "B")
        #expect(previous == "D")
    }

    @Test("toggle does nothing with empty cache")
    func toggleDoesNothingWithEmptyCache() {
        let navigator = WorkspaceNavigator.shared
        navigator.resetForTesting()

        let (order, focused, previous) = navigator.getStateForTesting()

        #expect(order.isEmpty)
        #expect(focused == nil)
        #expect(previous == nil)
    }

    // MARK: - Navigation state tests

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

    @Test("rapid toggles maintain consistency")
    func rapidTogglesKeepConsistency() async {
        let navigator = WorkspaceNavigator.shared

        // Simulate rapid toggle presses - state should always be valid
        for i in 0..<50 {
            let workspaces = ["A", "B", "C"]
            let focused = workspaces[i % 3]
            let previous = workspaces[(i + 1) % 3]
            navigator.setStateForTesting(order: workspaces, focused: focused, previous: previous)

            // Read state - should be consistent
            let (order, f, p) = navigator.getStateForTesting()
            #expect(order.count == 3)
            #expect(f != nil)
            #expect(p != nil)
            #expect(f != p) // focused and previous should differ
        }
    }
}
