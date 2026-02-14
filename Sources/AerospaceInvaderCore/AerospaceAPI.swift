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
            return "AeroSpace is not installed. Install it with: brew install --cask nikitabobko/tap/aerospace"
        case .notRunning:
            return "AeroSpace is not running and could not be started."
        case .commandFailed(let detail):
            return "AeroSpace command failed: \(detail)"
        case .timeout:
            return "AeroSpace command timed out."
        }
    }
}

/// Interacts with the AeroSpace CLI via shell commands.
/// All blocking operations use a 5-second timeout to prevent hangs.
public class AerospaceAPI: AerospaceCommandExecutor {
    /// Shared singleton for production use.
    public static let shared = AerospaceAPI()

    /// Default timeout for CLI commands, in seconds.
    private let processTimeout: TimeInterval = 5.0

    // Known Homebrew paths
    private let armPath = "/opt/homebrew/bin/aerospace"
    private let intelPath = "/usr/local/bin/aerospace"

    public init() {}

    // MARK: - Binary Discovery

    /// Returns the path to the aerospace binary, checking Homebrew paths and $PATH.
    /// - Returns: Absolute path to the binary, or nil if not found.
    public var aerospacePath: String? {
        if FileManager.default.fileExists(atPath: armPath) {
            return armPath
        }
        if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        // Fall back to $PATH lookup
        return resolveFromPath()
    }

    /// Searches `$PATH` for the aerospace binary using `which`.
    /// - Returns: Absolute path if found, nil otherwise.
    private func resolveFromPath() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["aerospace"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    public var isInstalled: Bool {
        aerospacePath != nil
    }

    // MARK: - Process Execution

    /// Runs an aerospace CLI command with a timeout.
    /// - Parameters:
    ///   - arguments: CLI arguments to pass after the binary path.
    ///   - captureOutput: Whether to capture stdout (default true).
    /// - Returns: Trimmed stdout string on success, nil on failure/timeout.
    private func run(arguments: [String], captureOutput: Bool = true) -> String? {
        guard let path = aerospacePath else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice

        let pipe = captureOutput ? Pipe() : nil
        task.standardOutput = captureOutput ? pipe : FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            fputs("aerospace: failed to launch — \(error.localizedDescription)\n", stderr)
            return nil
        }

        // Wait with timeout instead of indefinite waitUntilExit()
        let completed = waitForProcess(task, timeout: processTimeout)
        if !completed {
            task.terminate()
            fputs("aerospace: command timed out — \(arguments.joined(separator: " "))\n", stderr)
            return nil
        }

        if task.terminationStatus != 0 {
            fputs("aerospace: exit code \(task.terminationStatus) — \(arguments.joined(separator: " "))\n", stderr)
            return nil
        }

        guard let pipe = pipe else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fires an aerospace command without waiting for completion.
    /// Used for commands like `workspace` where we don't need the result.
    /// - Parameter arguments: CLI arguments to pass after the binary path.
    private func fireAndForget(arguments: [String]) {
        guard let path = aerospacePath else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            fputs("aerospace: failed to launch — \(error.localizedDescription)\n", stderr)
        }
    }

    /// Waits for a process to exit within the given timeout.
    /// - Parameters:
    ///   - process: The process to wait on.
    ///   - timeout: Maximum seconds to wait.
    /// - Returns: True if the process exited before the timeout.
    private func waitForProcess(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        let result = semaphore.wait(timeout: .now() + timeout)
        return result == .success
    }

    // MARK: - AerospaceCommandExecutor Conformance

    public func ensureEnabled() -> Result<Void, AerospaceError> {
        guard aerospacePath != nil else {
            return .failure(.notInstalled)
        }

        // Try a simple command to check if aerospace is responding
        if let output = run(arguments: ["list-workspaces", "--focused"]),
           !output.isEmpty {
            return .success(())
        }

        // Not responding — try to enable
        return enableAerospace()
    }

    /// Attempts to enable AeroSpace if it's installed but not running.
    /// - Returns: Success or a typed error.
    private func enableAerospace() -> Result<Void, AerospaceError> {
        guard aerospacePath != nil else {
            return .failure(.notInstalled)
        }

        fputs("Aerospace not responding, enabling...\n", stderr)

        guard run(arguments: ["enable", "on"]) != nil else {
            return .failure(.notRunning)
        }

        // Give it a moment to initialize — on a background queue to avoid blocking main
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

        var workspaces: [String] = []
        var focused: String?

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|")
            guard parts.count >= 2 else { continue }
            let ws = String(parts[0])
            workspaces.append(ws)
            if parts[1] == "true" {
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
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }

    public func getCurrentMode() -> String? {
        run(arguments: ["list-modes", "--current"])
    }
}
