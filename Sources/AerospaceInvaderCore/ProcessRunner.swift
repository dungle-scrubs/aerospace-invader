import Foundation

/// Deep adapter that owns `Process` orchestration — timeout, terminationHandler ordering,
/// pipe-drain deadlock avoidance, and output decoding. Previously this was scattered across
/// `AerospaceAPI.run` and `fireAndForget` with duplicated pipe handling. Now one module
/// owns every edge: a child that exits quickly, a child that floods stdout, a child that
/// times out. Tests inject a stub runner that returns canned stdout without launching a process.
///
/// Two adapters justify this seam: the production `ProcessRunner` and an in-memory stub in tests.
public class ProcessRunner {
    /// Default timeout for CLI commands.
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 5.0) {
        self.timeout = timeout
    }

    // MARK: - Factory helpers (static so BinaryResolver can reuse them without an instance)

    /// Builds a `Process` for `executable` with the given arguments.
    static func makeProcess(executable: String, arguments: [String], stdout: Pipe?) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = stdout ?? FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        return task
    }

    /// Decodes process output to a trimmed UTF-8 string (empty if it can't be decoded).
    static func decodeOutput(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Execution

    /// Runs a command with a timeout, capturing stdout.
    /// - Returns: Trimmed stdout on success, nil on failure/timeout.
    public func run(executable: String, arguments: [String], captureOutput: Bool = true) -> String? {
        let pipe = captureOutput ? Pipe() : nil
        let task = Self.makeProcess(executable: executable, arguments: arguments, stdout: pipe)

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

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

        if exited.wait(timeout: .now() + timeout) != .success {
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
        return Self.decodeOutput(outputData)
    }

    /// Fires a command without waiting for completion.
    public func fireAndForget(executable: String, arguments: [String]) {
        let task = Self.makeProcess(executable: executable, arguments: arguments, stdout: nil)
        do {
            try task.run()
        } catch {
            fputs("aerospace: failed to launch — \(error.localizedDescription)\n", stderr)
        }
    }
}

/// A stub runner for tests — returns canned output without launching a process.
public final class StubProcessRunner: ProcessRunner {
    public var cannedOutput: [String: String] = [:]
    public var recordedCommands: [[String]] = []

    public override func run(executable: String, arguments: [String], captureOutput: Bool = true) -> String? {
        recordedCommands.append(arguments)
        let key = arguments.joined(separator: " ")
        if let canned = cannedOutput[key] { return canned }
        return super.run(executable: executable, arguments: arguments, captureOutput: captureOutput)
    }

    public override func fireAndForget(executable: String, arguments: [String]) {
        recordedCommands.append(arguments)
        let key = arguments.joined(separator: " ")
        if cannedOutput[key] != nil { return }
        super.fireAndForget(executable: executable, arguments: arguments)
    }
}
