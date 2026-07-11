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

/// Interacts with the AeroSpace CLI via shell commands.
/// All blocking operations use a 5-second timeout to prevent hangs.
public final class AerospaceAPI: AerospaceCommandExecutor {
    /// Shared singleton for production use.
    public static let shared = AerospaceAPI()

    /// Default timeout for CLI commands, in seconds.
    private let processTimeout: TimeInterval = 5.0

    // Known install paths, checked before falling back to $PATH.
    private let armPath = "/opt/homebrew/bin/aerospace"
    private let intelPath = "/usr/local/bin/aerospace"

    /// Serializes access to the resolved-path cache.
    private let pathLock = NSLock()
    /// Cached result of binary discovery (`.some(nil)` means "resolved to not-found").
    private var _resolvedPath: String??

    public init() {}

    // MARK: - Binary Discovery

    /// Returns the path to the aerospace binary, checking known install paths and `$PATH`.
    /// The result is resolved once and cached, so a single planted `$PATH` binary can't be
    /// silently swapped in on a later call, and repeated commands don't re-run discovery.
    /// - Returns: Absolute path to the binary, or nil if not found.
    public var aerospacePath: String? {
        pathLock.lock()
        defer { pathLock.unlock() }
        if let cached = _resolvedPath {
            return cached
        }
        let resolved = discoverPath()
        _resolvedPath = .some(resolved)
        if let resolved = resolved {
            fputs("aerospace: using binary at \(resolved)\n", stderr)
        }
        return resolved
    }

    /// Resolves the aerospace binary path from known install locations, then `$PATH`.
    private func discoverPath() -> String? {
        if FileManager.default.fileExists(atPath: armPath) {
            return armPath
        }
        if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        return resolveFromPath()
    }

    /// Searches `$PATH` for the aerospace binary using `which`, then validates the candidate.
    /// - Returns: Absolute path if found and trusted, nil otherwise.
    private func resolveFromPath() -> String? {
        let pipe = Pipe()
        let task = makeProcess(executable: "/usr/bin/which", arguments: ["aerospace"], stdout: pipe)

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = decodeOutput(data)
        guard !path.isEmpty, isTrustedExecutable(path) else {
            if !path.isEmpty {
                fputs("aerospace: refusing to use untrusted binary at \(path) (writable by group/other)\n", stderr)
            }
            return nil
        }
        return path
    }

    /// Validates that a `$PATH`-resolved candidate is safe to execute: an absolute path to an
    /// existing executable file whose file and directory are not writable by group or other.
    /// This prevents a planted `aerospace` on an attacker-controlled `$PATH` entry from being run.
    private func isTrustedExecutable(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        guard fm.isExecutableFile(atPath: path) else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        return !isWritableByOthers(path) && !isWritableByOthers(parent)
    }

    /// True if the item at `path` is group- or other-writable (or its permissions can't be read).
    private func isWritableByOthers(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value else {
            return true
        }
        return (perms & 0o022) != 0
    }

    /// Builds a `Process` for `executable` with the given arguments, discarding stderr.
    /// - Parameter stdout: A `Pipe` to capture stdout, or `nil` to discard it.
    private func makeProcess(executable: String, arguments: [String], stdout: Pipe?) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = stdout ?? FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        return task
    }

    /// Decodes process output to a trimmed UTF-8 string (empty if it can't be decoded).
    private func decodeOutput(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

        let pipe = captureOutput ? Pipe() : nil
        let task = makeProcess(executable: path, arguments: arguments, stdout: pipe)

        // Install the termination handler BEFORE launching. If it were set after `run()`,
        // a command that exits before the assignment would never signal, forcing a full
        // timeout on otherwise-instant commands.
        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

        // Drain stdout concurrently so a child that writes more than the OS pipe buffer
        // (~64KB) can't block on `write()` while we wait for it to exit — a classic deadlock.
        var outputData = Data()
        let drained = DispatchSemaphore(value: 0)
        if let pipe = pipe {
            DispatchQueue.global(qos: .userInitiated).async {
                outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                drained.signal()
            }
        }

        do {
            try task.run()
        } catch {
            fputs("aerospace: failed to launch — \(error.localizedDescription)\n", stderr)
            return nil
        }

        if exited.wait(timeout: .now() + processTimeout) != .success {
            task.terminate()
            if pipe != nil { _ = drained.wait(timeout: .now() + 1.0) }
            fputs("aerospace: command timed out — \(arguments.joined(separator: " "))\n", stderr)
            return nil
        }

        if task.terminationStatus != 0 {
            if pipe != nil { _ = drained.wait(timeout: .now() + 1.0) }
            fputs("aerospace: exit code \(task.terminationStatus) — \(arguments.joined(separator: " "))\n", stderr)
            return nil
        }

        guard pipe != nil else { return "" }
        drained.wait()
        return decodeOutput(outputData)
    }

    /// Fires an aerospace command without waiting for completion.
    /// Used for commands like `workspace` where we don't need the result.
    /// - Parameter arguments: CLI arguments to pass after the binary path.
    private func fireAndForget(arguments: [String]) {
        guard let path = aerospacePath else { return }

        let task = makeProcess(executable: path, arguments: arguments, stdout: nil)

        do {
            try task.run()
        } catch {
            fputs("aerospace: failed to launch — \(error.localizedDescription)\n", stderr)
        }
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

        // Give AeroSpace a moment to initialize before the caller queries it. This runs
        // synchronously on the calling thread (ensureEnabled is invoked once at launch).
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
    /// - Parameter output: Raw stdout from `list-workspaces`.
    /// - Returns: Ordered workspace names and the focused workspace (last line marked `true`, if any).
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
