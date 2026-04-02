import Foundation

/// A specialized wrapper for starting long-running daemon processes, 
/// used specifically for the XPC Host connection and Copilot CLI inference.
/// Placed here to ensure `Process()` allocations are localized to the execution boundary layer.
public final class DaemonProcess: @unchecked Sendable {
    private let process: Foundation.Process
    public let stdinHandle: FileHandle
    public let stdoutHandle: FileHandle
    public let stderrHandle: FileHandle

    public init(executableURL: URL, arguments: [String] = [], currentDirectoryURL: URL? = nil, environment: [String: String]? = nil) throws {
        let p = Foundation.Process()
        p.executableURL = executableURL
        if let currentDirectoryURL = currentDirectoryURL {
            p.currentDirectoryURL = currentDirectoryURL
        }
        p.arguments = arguments
        if let environment = environment {
            p.environment = environment
        }
        
        let pipeIn = Pipe()
        let pipeOut = Pipe()
        let pipeErr = Pipe()
        
        p.standardInput = pipeIn
        p.standardOutput = pipeOut
        p.standardError = pipeErr
        
        self.process = p
        self.stdinHandle = pipeIn.fileHandleForWriting
        self.stdoutHandle = pipeOut.fileHandleForReading
        self.stderrHandle = pipeErr.fileHandleForReading
        
        try self.process.run()
    }
    
    public func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
    
    public var isRunning: Bool {
        return process.isRunning
    }

    public var terminationHandler: (@Sendable (DaemonProcess) -> Void)? {
        get {
            guard let handler = process.terminationHandler else { return nil }
            return { _ in handler(self.process) }
        }
        set { 
            if let newValue = newValue {
                process.terminationHandler = { _ in newValue(self) }
            } else {
                process.terminationHandler = nil
            }
        }
    }
    
    public var terminationStatus: Int32 {
        return process.terminationStatus
    }
}