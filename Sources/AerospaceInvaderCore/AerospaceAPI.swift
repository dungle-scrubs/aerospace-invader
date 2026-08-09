import Foundation

/// Errors originating from AeroSpace CLI interaction.
public enum AerospaceError: Error, CustomStringConvertible {
    case notInstalled
    case notRunning
    case commandFailed(String)
    case timeout

    public var description: String {
        switch self {
        case .notInstalled:
            return "AeroSpace is not installed. Install it from https://github.com/nikitabobko/AeroSpace#installation"
        case .notRunning:
            return "AeroSpace is not running and could not be started."
        case .commandFailed(let detail):
            return "AeroSpace command failed: \(detail)"
        case .timeout:
            return "AeroSpace command timed out."
        }
    }
}

/// Interacts with the AeroSpace CLI via `BinaryResolver` + `ProcessRunner` — two deep adapters
/// that own every file-system and process edge. Previously this class owned both concerns
/// directly (binary trust checks + timeout + pipe-drain) and its implementation was nearly as
/// wide as its interface (9 methods mirroring CLI verbs). Now those edges live behind clear
/// seams and the API concentrates domain mapping (what a workspace list means, how bindings
/// parse). Two adapters justify the seams: production implementations and in-memory stubs.
///
/// Callers see a stable `AerospaceCommandExecutor` interface; adding a new query reuses the
/// runner+resolver without exposing argument arrays.
public final class AerospaceAPI: AerospaceCommandExecutor {
    /// Shared singleton for production use.
    public static let shared = AerospaceAPI()

    private let resolver: BinaryResolver
    private let runner: ProcessRunner

    /// Production initializer.
    public init() {
        self.resolver = BinaryResolver()
        self.runner = ProcessRunner(timeout: 5.0)
    }

    /// Test initializer — inject explicit collaborators.
    public init(resolver: BinaryResolver = BinaryResolver(), runner: ProcessRunner = ProcessRunner()) {
        self.resolver = resolver
        self.runner = runner
    }

    // MARK: - Binary Discovery (delegates to BinaryResolver)

    /// Returns the path to the aerospace binary, checking known install paths and `$PATH`.
    /// Delegates to `BinaryResolver` so trust validation lives in one module.
    public var aerospacePath: String? { resolver.path }

    public var isInstalled: Bool { aerospacePath != nil }

    // MARK: - Process Execution (delegates to ProcessRunner)

    /// Runs an aerospace CLI command with a timeout.
    private func run(arguments: [String], captureOutput: Bool = true) -> String? {
        guard let path = aerospacePath else { return nil }
        return runner.run(executable: path, arguments: arguments, captureOutput: captureOutput)
    }

    /// Fires an aerospace command without waiting for completion.
    private func fireAndForget(arguments: [String]) {
        guard let path = aerospacePath else { return }
        runner.fireAndForget(executable: path, arguments: arguments)
    }

    // MARK: - AerospaceCommandExecutor Conformance

    public func ensureEnabled() -> Result<Void, AerospaceError> {
        guard aerospacePath != nil else {
            return .failure(.notInstalled)
        }

        if let output = run(arguments: ["list-workspaces", "--focused"]),
           !output.isEmpty {
            return .success(())
        }

        return enableAerospace()
    }

    private func enableAerospace() -> Result<Void, AerospaceError> {
        guard aerospacePath != nil else {
            return .failure(.notInstalled)
        }

        fputs("Aerospace not responding, enabling...\n", stderr)

        guard run(arguments: ["enable", "on"]) != nil else {
            return .failure(.notRunning)
        }

        Thread.sleep(forTimeInterval: 0.5)
        return .success(())
    }

    public func getWorkspacesWithFocus() -> (workspaces: [String], focused: String?) {
        guard let output = run(arguments: [
            "list-workspaces", "--monitor", "all", "--empty", "no",
            "--format", "%{workspace}|%{workspace-is-focused}"
        ]) else {
            return ([], nil)
        }
        return AerospaceAPI.parseWorkspaceOutput(output)
    }

    /// Parses the `%{workspace}|%{workspace-is-focused}` CLI output into workspaces and the
    /// focused one. Pure and side-effect-free so it can be unit-tested without the CLI.
    static func parseWorkspaceOutput(_ output: String) -> (workspaces: [String], focused: String?) {
        var workspaces: [String] = []
        var focused: String?

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|")
            guard parts.count >= 2 else { continue }
            let ws = parts[0].trimmingCharacters(in: .whitespaces)
            guard !ws.isEmpty else { continue }
            workspaces.append(ws)
            if parts[1].trimmingCharacters(in: .whitespaces) == "true" {
                focused = ws
            }
        }

        return (workspaces, focused)
    }

    public func getNonEmptyWorkspaces() -> [String] {
        getWorkspacesWithFocus().workspaces
    }

    public func getCurrentWorkspace() -> String? {
        getWorkspacesWithFocus().focused
    }

    public func switchToWorkspace(_ workspace: String) {
        fireAndForget(arguments: ["workspace", workspace])
    }

    public func workspaceBackAndForth() {
        fireAndForget(arguments: ["workspace-back-and-forth"])
    }

    public func getBindings(mode: String) -> [String: String]? {
        guard let output = run(arguments: ["config", "--get", "mode.\(mode).binding", "--json"]) else {
            return nil
        }
        let data = Data(output.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let bindings = object as? [String: String] else {
            fputs("aerospace: failed to parse bindings JSON for mode '\(mode)'\n", stderr)
            return nil
        }
        return bindings
    }

    public func getCurrentMode() -> String? {
        run(arguments: ["list-modes", "--current"])
    }
}
