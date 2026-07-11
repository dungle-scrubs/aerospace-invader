@testable import AerospaceInvaderCore
import Foundation
import Testing

@Suite("AerospaceAPI")
struct AerospaceAPITests {

    // MARK: - Error descriptions

    @Test("notInstalled error has descriptive message")
    func notInstalledDescription() {
        let error = AerospaceError.notInstalled
        #expect(error.description.contains("not installed"))
        #expect(error.description.contains("github.com/nikitabobko/AeroSpace"))
    }

    @Test("notRunning error has descriptive message")
    func notRunningDescription() {
        let error = AerospaceError.notRunning
        #expect(error.description.contains("not running"))
    }

    @Test("commandFailed error includes detail")
    func commandFailedDescription() {
        let error = AerospaceError.commandFailed("workspace not found")
        #expect(error.description.contains("workspace not found"))
    }

    @Test("timeout error has descriptive message")
    func timeoutDescription() {
        let error = AerospaceError.timeout
        #expect(error.description.contains("timed out"))
    }

    // MARK: - Mock API behavior

    @Test("mock API returns configured workspaces")
    func mockReturnsWorkspaces() {
        let api = MockAerospaceAPI()
        api.workspacesWithFocus = (["1", "2", "3"], "2")

        let result = api.getWorkspacesWithFocus()
        #expect(result.workspaces == ["1", "2", "3"])
        #expect(result.focused == "2")
    }

    @Test("mock API records workspace switches")
    func mockRecordsSwitches() {
        let api = MockAerospaceAPI()
        api.switchToWorkspace("1")
        api.switchToWorkspace("3")

        #expect(api.switchedWorkspaces == ["1", "3"])
    }

    @Test("mock API getNonEmptyWorkspaces returns workspace list")
    func mockNonEmpty() {
        let api = MockAerospaceAPI()
        api.workspacesWithFocus = (["A", "B"], "A")

        #expect(api.getNonEmptyWorkspaces() == ["A", "B"])
    }

    @Test("mock API getCurrentWorkspace returns focused")
    func mockCurrentWorkspace() {
        let api = MockAerospaceAPI()
        api.workspacesWithFocus = (["A", "B"], "B")

        #expect(api.getCurrentWorkspace() == "B")
    }

    @Test("mock API ensureEnabled returns configured result")
    func mockEnsureEnabled() {
        let api = MockAerospaceAPI()
        api.ensureEnabledResult = .failure(.notInstalled)

        let result = api.ensureEnabled()
        if case .failure(let error) = result {
            #expect(error.description.contains("not installed"))
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("mock API with not installed returns empty workspaces")
    func mockNotInstalled() {
        let api = MockAerospaceAPI()
        api.isInstalled = false
        api.workspacesWithFocus = ([], nil)

        #expect(api.getNonEmptyWorkspaces().isEmpty)
        #expect(api.getCurrentWorkspace() == nil)
    }

    // MARK: - Workspace output parsing

    @Test("parse empty output yields no workspaces")
    func parseEmpty() {
        let result = AerospaceAPI.parseWorkspaceOutput("")
        #expect(result.workspaces.isEmpty)
        #expect(result.focused == nil)
    }

    @Test("parse identifies the focused workspace")
    func parseFocused() {
        let result = AerospaceAPI.parseWorkspaceOutput("A|false\nB|true\nC|false")
        #expect(result.workspaces == ["A", "B", "C"])
        #expect(result.focused == "B")
    }

    @Test("parse with no focused line yields nil focus")
    func parseNoFocus() {
        let result = AerospaceAPI.parseWorkspaceOutput("A|false\nB|false")
        #expect(result.workspaces == ["A", "B"])
        #expect(result.focused == nil)
    }

    @Test("parse with multiple focused lines takes the last")
    func parseMultipleFocused() {
        let result = AerospaceAPI.parseWorkspaceOutput("A|true\nB|true")
        #expect(result.workspaces == ["A", "B"])
        #expect(result.focused == "B")
    }

    @Test("parse drops malformed lines")
    func parseMalformed() {
        let result = AerospaceAPI.parseWorkspaceOutput("A|true\nB\n\nC|false")
        #expect(result.workspaces == ["A", "C"])
        #expect(result.focused == "A")
    }

    @Test("parse tolerates CRLF and surrounding whitespace")
    func parseWhitespace() {
        let result = AerospaceAPI.parseWorkspaceOutput("A|false\r\n B | true \r\nC|false")
        #expect(result.workspaces == ["A", "B", "C"])
        #expect(result.focused == "B")
    }
}
