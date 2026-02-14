@testable import AerospaceInvaderCore
import Foundation
import Testing

@Suite("WorkspaceNavigator", .serialized)
struct WorkspaceNavigatorTests {

    // MARK: - Helpers

    /// Creates a navigator with mock dependencies and pre-populated state.
    private func makeNavigator(
        workspaces: [String] = ["A", "B", "C"],
        focused: String? = "B",
        savedOrder: [String]? = nil
    ) -> (WorkspaceNavigator, MockAerospaceAPI, MockOrderProvider) {
        let api = MockAerospaceAPI()
        api.workspacesWithFocus = (workspaces, focused)

        let order = MockOrderProvider()
        order.savedOrder = savedOrder ?? workspaces

        let navigator = WorkspaceNavigator(api: api, orderProvider: order)
        navigator.setStateForTesting(order: savedOrder ?? workspaces, focused: focused, previous: nil)

        return (navigator, api, order)
    }

    // MARK: - Back navigation

    @Test("back navigates to previous workspace")
    func backNavigatesToPrevious() async {
        let (navigator, api, _) = makeNavigator(focused: "B")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.back { order, current in
                #expect(current == "A")
                #expect(order == ["A", "B", "C"])
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("A"))
    }

    @Test("back wraps around from first to last")
    func backWrapsAround() async {
        let (navigator, api, _) = makeNavigator(focused: "A")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.back { _, current in
                #expect(current == "C")
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("C"))
    }

    @Test("back with single workspace stays on same")
    func backSingleWorkspace() async {
        let (navigator, api, _) = makeNavigator(workspaces: ["A"], focused: "A")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.back { _, current in
                #expect(current == "A")
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("A"))
    }

    @Test("back with empty cache does not crash")
    func backEmptyCache() {
        let (navigator, api, _) = makeNavigator(workspaces: [], focused: nil, savedOrder: [])
        navigator.resetForTesting()

        // Should not call completion synchronously when cache is empty
        var called = false
        navigator.back { _, _ in called = true }

        // The sync path should not have been called
        #expect(!called)
        #expect(api.switchedWorkspaces.isEmpty)
    }

    // MARK: - Forward navigation

    @Test("forward navigates to next workspace")
    func forwardNavigatesToNext() async {
        let (navigator, api, _) = makeNavigator(focused: "B")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.forward { _, current in
                #expect(current == "C")
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("C"))
    }

    @Test("forward wraps around from last to first")
    func forwardWrapsAround() async {
        let (navigator, api, _) = makeNavigator(focused: "C")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.forward { _, current in
                #expect(current == "A")
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("A"))
    }

    @Test("forward with single workspace stays on same")
    func forwardSingleWorkspace() async {
        let (navigator, api, _) = makeNavigator(workspaces: ["X"], focused: "X")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.forward { _, current in
                #expect(current == "X")
                continuation.resume()
            }
        }

        #expect(api.switchedWorkspaces.contains("X"))
    }

    // MARK: - Toggle

    @Test("toggle calls workspaceBackAndForth")
    func toggleCallsBackAndForth() {
        let (navigator, api, _) = makeNavigator()
        navigator.toggle { _, _ in }
        #expect(api.backAndForthCallCount == 1)
    }

    // MARK: - Sync navigation

    @Test("sync back returns correct result")
    func syncBack() {
        let (navigator, api, _) = makeNavigator(focused: "B")
        let result = navigator.back()
        #expect(result.current == "A")
        #expect(result.order == ["A", "B", "C"])
        #expect(api.switchedWorkspaces.contains("A"))
    }

    @Test("sync forward returns correct result")
    func syncForward() {
        let (navigator, api, _) = makeNavigator(focused: "B")
        let result = navigator.forward()
        #expect(result.current == "C")
        #expect(result.order == ["A", "B", "C"])
        #expect(api.switchedWorkspaces.contains("C"))
    }

    @Test("sync back wraps around")
    func syncBackWraps() {
        let (navigator, _, _) = makeNavigator(focused: "A")
        let result = navigator.back()
        #expect(result.current == "C")
    }

    @Test("sync forward wraps around")
    func syncForwardWraps() {
        let (navigator, _, _) = makeNavigator(focused: "C")
        let result = navigator.forward()
        #expect(result.current == "A")
    }

    @Test("sync navigation with empty workspaces returns empty")
    func syncEmptyWorkspaces() {
        let api = MockAerospaceAPI()
        api.workspacesWithFocus = ([], nil)
        let order = MockOrderProvider()
        let navigator = WorkspaceNavigator(api: api, orderProvider: order)

        let result = navigator.back()
        #expect(result.order.isEmpty)
        #expect(result.current == nil)
    }

    // MARK: - State management

    @Test("reset clears all state")
    func resetClearsAllState() {
        let (navigator, _, _) = makeNavigator()
        navigator.resetForTesting()

        let (order, focused, previous) = navigator.getStateForTesting()
        #expect(order.isEmpty)
        #expect(focused == nil)
        #expect(previous == nil)
    }

    @Test("navigation updates previous workspace tracking")
    func navigationTracksPrevious() async {
        let (navigator, _, _) = makeNavigator(focused: "B")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            navigator.forward { _, _ in
                continuation.resume()
            }
        }

        let (_, _, previous) = navigator.getStateForTesting()
        #expect(previous == "B")
    }

    // MARK: - Thread safety

    @Test("concurrent state access is safe")
    func concurrentStateAccessIsSafe() async {
        let (navigator, _, _) = makeNavigator()

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

        let (order, _, _) = navigator.getStateForTesting()
        #expect(order.count == 3)
    }
}
