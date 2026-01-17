import Foundation

public enum AerospaceError: Error, CustomStringConvertible {
    case notInstalled
    case notRunning
    case commandFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            return "AeroSpace is not installed. Install it with: brew install --cask nikitabobko/tap/aerospace"
        case .notRunning:
            return "AeroSpace is not running and could not be started."
        case .commandFailed(let detail):
            return "AeroSpace command failed: \(detail)"
        }
    }
}

public class AerospaceAPI {
    // Apple Silicon (Homebrew)
    private static let armPath = "/opt/homebrew/bin/aerospace"
    // Intel Mac (Homebrew)
    private static let intelPath = "/usr/local/bin/aerospace"

    /// Returns the path to the aerospace binary, or nil if not installed.
    public static var aerospacePath: String? {
        if FileManager.default.fileExists(atPath: armPath) {
            return armPath
        } else if FileManager.default.fileExists(atPath: intelPath) {
            return intelPath
        }
        return nil
    }

    /// Check if aerospace binary is installed.
    public static var isInstalled: Bool {
        aerospacePath != nil
    }

    /// Check if aerospace is enabled by trying to list workspaces.
    /// If it fails, enable aerospace.
    public static func ensureEnabled() -> Result<Void, AerospaceError> {
        guard let path = aerospacePath else {
            return .failure(.notInstalled)
        }

        // Try a simple command to check if aerospace is responding
        let checkTask = Process()
        checkTask.executableURL = URL(fileURLWithPath: path)
        checkTask.arguments = ["list-workspaces", "--focused"]

        let pipe = Pipe()
        checkTask.standardOutput = pipe
        checkTask.standardError = FileHandle.nullDevice

        do {
            try checkTask.run()
            checkTask.waitUntilExit()
        } catch {
            // Aerospace not running at all, try to enable
            return enableAerospace()
        }

        // If exit code is non-zero or no output, try enabling
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if checkTask.terminationStatus == 0 && !output.isEmpty {
            return .success(())
        }

        return enableAerospace()
    }

    private static func enableAerospace() -> Result<Void, AerospaceError> {
        guard let path = aerospacePath else {
            return .failure(.notInstalled)
        }

        fputs("Aerospace not responding, enabling...\n", stderr)
        let enableTask = Process()
        enableTask.executableURL = URL(fileURLWithPath: path)
        enableTask.arguments = ["enable", "on"]
        enableTask.standardOutput = FileHandle.nullDevice
        enableTask.standardError = FileHandle.nullDevice

        do {
            try enableTask.run()
            enableTask.waitUntilExit()
            // Give it a moment to initialize
            Thread.sleep(forTimeInterval: 0.5)
            return .success(())
        } catch {
            return .failure(.notRunning)
        }
    }

    /// Returns (workspaces, focusedWorkspace) in a single CLI call
    public static func getWorkspacesWithFocus() -> (workspaces: [String], focused: String?) {
        guard let path = aerospacePath else { return ([], nil) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["list-workspaces", "--monitor", "all", "--empty", "no", "--format", "%{workspace}|%{workspace-is-focused}"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return ([], nil) }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

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

    public static func getNonEmptyWorkspaces() -> [String] {
        return getWorkspacesWithFocus().workspaces
    }

    public static func getCurrentWorkspace() -> String? {
        return getWorkspacesWithFocus().focused
    }

    public static func switchToWorkspace(_ ws: String) {
        guard let path = aerospacePath else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["workspace", ws]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        // Don't wait - fire and forget
    }

    public static func workspaceBackAndForth() {
        guard let path = aerospacePath else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["workspace-back-and-forth"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        // Don't wait - fire and forget
    }

    public static func getBindings(mode: String) -> [String: String]? {
        guard let path = aerospacePath else { return nil }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = ["config", "--get", "mode.\(mode).binding", "--json"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONSerialization.jsonObject(with: data) as? [String: String]
    }
}
