import Foundation

public final class DefaultProcessAdapter: ProcessAdapter {
    private let policyEngine: PolicyEngine
    
    /// Maximum output size per stream (stdout/stderr). Prevents memory exhaustion from runaway processes.
    /// Default 10MB should handle most legitimate outputs while protecting against infinite streams.
    public static let defaultMaxOutputBytes: Int = 10 * 1024 * 1024
    
    /// Default timeout for process execution. 60 seconds is generous for most commands.
    public static let defaultTimeoutSeconds: TimeInterval = 60

    public init(policyEngine: PolicyEngine = PolicyEngine.shared) {
        self.policyEngine = policyEngine
    }

    public func run(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy? = nil) async throws -> ProcessResult {
        return try await runWithTimeout(
            command,
            in: workspace,
            timeout: policy?.timeoutSeconds ?? Self.defaultTimeoutSeconds,
            maxOutputBytes: policy?.maxOutputBytes ?? Self.defaultMaxOutputBytes
        )
    }

    /// Run a command with proper concurrent pipe draining to avoid deadlocks.
    /// Pipes are drained concurrently while the process runs, preventing buffer exhaustion.
    public func runWithTimeout(
        _ command: SystemCommand,
        in workspace: WorkspaceContext?,
        timeout: TimeInterval = defaultTimeoutSeconds,
        maxOutputBytes: Int = defaultMaxOutputBytes
    ) async throws -> ProcessResult {
        let process = Foundation.Process()
        process.currentDirectoryURL = workspace?.rootURL
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = sanitizedEnvironment()

        let start = Date()

        // Start the process
        try process.run()
        
        // Drain pipes concurrently to prevent deadlock.
        // Key insight: we must read from pipes WHILE the process runs,
        // not after waitUntilExit(). If pipes fill (64KB), process blocks.
        async let stdoutDrain = drainPipe(stdout, maxBytes: maxOutputBytes)
        async let stderrDrain = drainPipe(stderr, maxBytes: maxOutputBytes)
        
        // Wait for process with timeout
        let completed = await waitForProcess(process, timeout: timeout)
        var terminationReason: ProcessTerminationReason = .exit
        
        if !completed {
            terminationReason = .timeout
            process.terminate()
            // Give it a moment to clean up
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            if process.isRunning {
                process.interrupt() // SIGINT
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            // A final forced stop path if the process is STILL running
            // kill() can be called using Task {} or just kill command
            // or simply wait if it is killed. process.terminate() is SIGTERM.
            // There's no forced kill(SIGKILL) exposed on `Process` directly, 
            // but we can execute kill -9 pid
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        } else if process.terminationReason == .uncaughtSignal {
            terminationReason = .uncaughtSignal
        }
        
        // Collect drained output
        let outDrain = await stdoutDrain
        let errDrain = await stderrDrain

        let exitCode = completed ? process.terminationStatus : -1
        let durationMs = Date().timeIntervalSince(start) * 1000.0

        var errString = String(data: errDrain.data, encoding: .utf8) ?? ""
        if !completed {
            errString += "\n[Oracle OS: Process timed out after \(Int(timeout))s]"
        }

        return ProcessResult(
            exitCode: exitCode,
            stdout: String(data: outDrain.data, encoding: .utf8) ?? "",
            stderr: errString,
            durationMs: durationMs,
            timedOut: !completed,
            terminationReason: terminationReason,
            stdoutTruncated: outDrain.truncated,
            stderrTruncated: errDrain.truncated
        )
    }
    
    /// Synchronous version for backward compatibility - uses dispatch queues for concurrent draining.
    public func runSync(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy? = nil) throws -> ProcessResult {
        let process = Foundation.Process()
        process.currentDirectoryURL = workspace?.rootURL
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = sanitizedEnvironment()

        // Start process FIRST, then drain pipes concurrently
        try process.run()
        
        // Concurrent pipe draining using dispatch queues
        // IMPORTANT: Pipes must be drained WHILE process runs to prevent buffer deadlock
        final class DrainResult: @unchecked Sendable {
            var data: Data = Data()
            var truncated: Bool = false
        }
        let stdoutRes = DrainResult()
        let stderrRes = DrainResult()
        let maxBytes = Self.defaultMaxOutputBytes
        
        let stdoutQueue = DispatchQueue(label: "oracle.process.stdout")
        let stderrQueue = DispatchQueue(label: "oracle.process.stderr")
        let group = DispatchGroup()
        
        let start = Date()

        group.enter()
        stdoutQueue.async {
            let res = self.drainPipeSync(stdout, maxBytes: maxBytes)
            stdoutRes.data = res.data
            stdoutRes.truncated = res.truncated
            group.leave()
        }
        
        group.enter()
        stderrQueue.async {
            let res = self.drainPipeSync(stderr, maxBytes: maxBytes)
            stderrRes.data = res.data
            stderrRes.truncated = res.truncated
            group.leave()
        }
        
        // Wait for pipes to drain (they close when process exits)
        // Then wait for process to fully terminate
        group.wait()
        process.waitUntilExit()

        let durationMs = Date().timeIntervalSince(start) * 1000.0

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutRes.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrRes.data, encoding: .utf8) ?? "",
            durationMs: durationMs,
            timedOut: false,
            terminationReason: .exit,
            stdoutTruncated: stdoutRes.truncated,
            stderrTruncated: stderrRes.truncated
        )
    }
    
    // MARK: - Pipe Draining
    
    /// Drain a pipe asynchronously with bounded output.
    private func drainPipe(_ pipe: Pipe, maxBytes: Int) async -> (data: Data, truncated: Bool) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let res = self.drainPipeSync(pipe, maxBytes: maxBytes)
                continuation.resume(returning: res)
            }
        }
    }
    
    /// Drain a pipe synchronously with bounded output.
    private func drainPipeSync(_ pipe: Pipe, maxBytes: Int) -> (data: Data, truncated: Bool) {
        var accumulated = Data()
        var truncated = false
        let handle = pipe.fileHandleForReading
        
        // Read in chunks to allow for bounding
        let chunkSize = 64 * 1024 // 64KB chunks
        
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                break // EOF
            }
            
            let remaining = maxBytes - accumulated.count
            if remaining <= 0 {
                // Truncate - we've hit the limit
                truncated = true
                break
            }
            
            if chunk.count <= remaining {
                accumulated.append(chunk)
            } else {
                accumulated.append(chunk.prefix(remaining))
                truncated = true
                break
            }
        }
        
        return (data: accumulated, truncated: truncated)
    }
    
    /// Wait for a process to exit with timeout.
    private func waitForProcess(_ process: Foundation.Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        
        // Poll for completion
        while process.isRunning {
            if Date() > deadline {
                return false // Timed out
            }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        return true
    }

    private struct DefaultBackgroundProcess: BackgroundProcess {
        let process: Foundation.Process
        var processIdentifier: Int32 { process.processIdentifier }
        func terminate() { process.terminate() }
    }

    public func spawnBackground(_ command: SystemCommand, in workspace: WorkspaceContext?) throws -> any BackgroundProcess {
        let process = Foundation.Process()
        process.currentDirectoryURL = workspace?.rootURL
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        process.environment = sanitizedEnvironment()
        try process.run()
        return DefaultBackgroundProcess(process: process)
    }

    private func sanitizedEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "DEVELOPER_DIR"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            source[key].map { (key, $0) }
        })
    }
}
