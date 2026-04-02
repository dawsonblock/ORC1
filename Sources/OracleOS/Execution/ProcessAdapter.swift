import Foundation

public struct SystemCommand: Sendable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum ProcessTerminationReason: Sendable, Equatable {
    case exit
    case uncaughtSignal
    case timeout
}

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let durationMs: Double
    public let timedOut: Bool
    public let terminationReason: ProcessTerminationReason
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        durationMs: Double = 0.0,
        timedOut: Bool = false,
        terminationReason: ProcessTerminationReason = .exit,
        stdoutTruncated: Bool = false,
        stderrTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
        self.timedOut = timedOut
        self.terminationReason = terminationReason
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
    }
}

public protocol BackgroundProcess: Sendable {
    var processIdentifier: Int32 { get }
    func terminate()
}

public struct CommandExecutionPolicy: Sendable, Equatable {
    public let timeoutSeconds: TimeInterval
    public let maxOutputBytes: Int

    public init(timeoutSeconds: TimeInterval, maxOutputBytes: Int) {
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }
}

public protocol ProcessAdapter: Sendable {
    func run(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy?) async throws -> ProcessResult
    func runSync(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy?) throws -> ProcessResult
    
    /// Spawns a background process and returns a handle.
    func spawnBackground(_ command: SystemCommand, in workspace: WorkspaceContext?) throws -> any BackgroundProcess
}
