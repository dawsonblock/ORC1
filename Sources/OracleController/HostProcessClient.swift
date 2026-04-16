import Foundation
import OracleControllerShared
import OracleOS

enum HostClientError: LocalizedError, Equatable {
    case hostBinaryNotFound(path: String?)
    case hostBinaryNotRunnable(path: String)
    case hostLaunchFailed(message: String)
    case hostPipeUnavailable
    case hostExited(status: Int32?)
    case hostProtocolViolation(message: String)
    case requestCancelled

    var errorDescription: String? {
        switch self {
        case .hostBinaryNotFound(let path):
            if let path {
                return
                    "OracleControllerHost override path \(path) could not be found. Rebuild the host helper or clear ORACLE_CONTROLLER_HOST_PATH."
            }
            return
                "OracleControllerHost could not be found. Install the bundled app helper or set ORACLE_CONTROLLER_HOST_PATH for development."
        case .hostBinaryNotRunnable(let path):
            return
                "OracleControllerHost exists at \(path) but is not executable. Check file permissions or the override path."
        case .hostLaunchFailed(let message):
            return "OracleControllerHost failed to launch. \(message)"
        case .hostPipeUnavailable:
            return "OracleControllerHost pipes are unavailable."
        case .hostExited(let status):
            if let status {
                return
                    "OracleControllerHost exited with status \(status). Retry to relaunch the local bridge."
            }
            return "OracleControllerHost stopped responding. Retry to relaunch the local bridge."
        case .hostProtocolViolation(let message):
            return "OracleControllerHost returned an invalid response. \(message)"
        case .requestCancelled:
            return "The request was cancelled before the host responded."
        }
    }

    var connectionStatus: HostConnectionStatus? {
        switch self {
        case .hostBinaryNotFound:
            return .failed(reason: .binaryNotFound, detail: errorDescription)
        case .hostBinaryNotRunnable:
            return .failed(reason: .binaryNotRunnable, detail: errorDescription)
        case .hostLaunchFailed:
            return .failed(reason: .launchFailed, detail: errorDescription)
        case .hostPipeUnavailable:
            return .failed(reason: .pipeUnavailable, detail: errorDescription)
        case .hostExited:
            return .disconnected(reason: .exited, detail: errorDescription)
        case .hostProtocolViolation:
            return .failed(reason: .protocolError, detail: errorDescription)
        case .requestCancelled:
            return nil
        }
    }
}

struct HostProcessResolutionContext: Sendable {
    let environment: [String: String]
    let bundledHelperURL: URL?
    let siblingHelperURL: URL
    let developerFallbackURLs: [URL]
    let launchCurrentDirectoryURL: URL

    static func live(fileManager: FileManager = .default) -> Self {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let currentDirectoryURL = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )

        return HostProcessResolutionContext(
            environment: ProcessInfo.processInfo.environment,
            bundledHelperURL: OracleProductPaths.bundledHelperURL,
            siblingHelperURL:
                executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("OracleControllerHost"),
            developerFallbackURLs: developerFallbackURLs(from: currentDirectoryURL),
            launchCurrentDirectoryURL: OracleProductPaths.runningFromAppBundle
                ? OracleProductPaths.dataRootDirectory
                : currentDirectoryURL
        )
    }

    static func developerFallbackURLs(from currentDirectoryURL: URL) -> [URL] {
        [
            currentDirectoryURL.appendingPathComponent(".build/debug/OracleControllerHost"),
            currentDirectoryURL.appendingPathComponent(
                ".build/arm64-apple-macosx/debug/OracleControllerHost"),
            currentDirectoryURL.appendingPathComponent(
                ".build/x86_64-apple-macosx/debug/OracleControllerHost"),
        ]
    }
}

actor HostProcessClient {
    typealias EventHandler = @MainActor @Sendable (ControllerHostEvent) -> Void
    typealias LifecycleHandler = @MainActor @Sendable (HostConnectionStatus) -> Void

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let eventHandler: EventHandler
    private let lifecycleHandler: LifecycleHandler
    private let hostResolutionContext: @Sendable () -> HostProcessResolutionContext

    private var process: DaemonProcess?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<ControllerHostResponse, any Error>] =
        [:]
    private var lifecycleStatus: HostConnectionStatus = .idle
    private var lastTerminationStatus: Int32?

    init(
        eventHandler: @escaping EventHandler,
        lifecycleHandler: @escaping LifecycleHandler,
        hostResolutionContext: @escaping @Sendable () -> HostProcessResolutionContext = {
            HostProcessResolutionContext.live()
        }
    ) {
        self.eventHandler = eventHandler
        self.lifecycleHandler = lifecycleHandler
        self.hostResolutionContext = hostResolutionContext
        self.encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.sortedKeys])
        self.decoder = ControllerJSONCoding.makeDecoder()
    }

    deinit {
        readTask?.cancel()
        process?.terminate()
    }

    func send(_ request: ControllerHostRequest) async throws -> ControllerHostResponse {
        try launchIfNeeded()
        guard let stdinHandle else {
            let error = HostClientError.hostPipeUnavailable
            updateLifecycleIfNeeded(for: error)
            throw error
        }

        let payload = try encodedLine(for: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingResponses[request.id] = continuation
                do {
                    try stdinHandle.write(contentsOf: payload)
                } catch {
                    pendingResponses.removeValue(forKey: request.id)
                    let resolved = transportError(from: error)
                    updateLifecycleIfNeeded(for: resolved)
                    continuation.resume(throwing: resolved)
                }
            }
        } onCancel: {
            Task {
                await self.cancelPending(requestID: request.id)
            }
        }
    }

    private func encodedLine(for request: ControllerHostRequest) throws -> Data {
        var data = try encoder.encode(request)
        data.append(0x0A)
        return data
    }

    private func launchIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

        updateLifecycle(.launching)

        let resolutionContext = hostResolutionContext()
        let hostURL: URL
        do {
            hostURL = try Self.resolveHostURL(using: resolutionContext)
        } catch {
            updateLifecycleIfNeeded(for: error)
            throw error
        }

        let process: DaemonProcess
        do {
            process = try DaemonProcess(
                executableURL: hostURL,
                currentDirectoryURL: resolutionContext.launchCurrentDirectoryURL
            )
        } catch {
            let launchError = HostClientError.hostLaunchFailed(message: error.localizedDescription)
            updateLifecycleIfNeeded(for: launchError)
            throw launchError
        }

        lastTerminationStatus = nil
        process.terminationHandler = { daemon in
            Task {
                await self.recordTermination(status: daemon.terminationStatus)
            }
        }

        self.process = process
        self.stdinHandle = process.stdinHandle
        self.stdoutHandle = process.stdoutHandle
        startReadLoop(process.stdoutHandle)
    }

    static func resolveHostURL(
        using context: HostProcessResolutionContext,
        fileManager: FileManager = .default
    ) throws -> URL {
        let fileManager = FileManager.default
        var firstNonRunnablePath: String?

        func rememberIfNonRunnable(_ url: URL) {
            guard firstNonRunnablePath == nil,
                fileManager.fileExists(atPath: url.path),
                !fileManager.isExecutableFile(atPath: url.path)
            else {
                return
            }
            firstNonRunnablePath = url.path
        }

        if let override = context.environment["ORACLE_CONTROLLER_HOST_PATH"],
            !override.isEmpty
        {
            let url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
            if fileManager.fileExists(atPath: url.path) {
                throw HostClientError.hostBinaryNotRunnable(path: url.path)
            }
            throw HostClientError.hostBinaryNotFound(path: url.path)
        }

        if let bundledHelperURL = context.bundledHelperURL {
            if fileManager.isExecutableFile(atPath: bundledHelperURL.path) {
                return bundledHelperURL
            }
            rememberIfNonRunnable(bundledHelperURL)
        }

        let candidates = [context.siblingHelperURL] + context.developerFallbackURLs

        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            rememberIfNonRunnable(candidate)
        }

        if let firstNonRunnablePath {
            throw HostClientError.hostBinaryNotRunnable(path: firstNonRunnablePath)
        }

        throw HostClientError.hostBinaryNotFound(path: nil)
    }

    private func startReadLoop(_ handle: FileHandle) {
        readTask?.cancel()
        readTask = Task { [decoder] in
            do {
                for try await line in handle.bytes.lines {
                    guard let data = line.data(using: .utf8), !data.isEmpty else {
                        continue
                    }
                    let envelope = try decoder.decode(ControllerHostEnvelope.self, from: data)
                    await self.route(envelope)
                }
                guard !Task.isCancelled else { return }
                self.handleOutputClosed()
            } catch {
                guard !Task.isCancelled else { return }
                self.handleOutputFailure(error)
            }
        }
    }

    private func route(_ envelope: ControllerHostEnvelope) async {
        updateLifecycle(.connected)

        if let response = envelope.response,
            let continuation = pendingResponses.removeValue(forKey: response.requestID)
        {
            continuation.resume(returning: response)
            return
        }

        if let event = envelope.event {
            await MainActor.run {
                eventHandler(event)
            }
        }
    }

    private func cancelPending(requestID: String) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: HostClientError.requestCancelled)
    }

    private func recordTermination(status: Int32) {
        lastTerminationStatus = status
    }

    private func handleOutputClosed() {
        let exitError = HostClientError.hostExited(status: lastTerminationStatus)
        clearProcessState()
        updateLifecycleIfNeeded(for: exitError)
        failPendingResponses(with: exitError)
    }

    private func handleOutputFailure(_ error: any Error) {
        let resolved: any Error

        if let hostError = error as? HostClientError {
            resolved = hostError
        } else if error is DecodingError {
            resolved = HostClientError.hostProtocolViolation(message: error.localizedDescription)
        } else if process?.isRunning != true {
            resolved = HostClientError.hostExited(status: lastTerminationStatus)
        } else {
            resolved = HostClientError.hostProtocolViolation(message: error.localizedDescription)
        }

        clearProcessState()
        updateLifecycleIfNeeded(for: resolved)
        failPendingResponses(with: resolved)
    }

    private func clearProcessState() {
        readTask = nil
        stdinHandle = nil
        stdoutHandle = nil
        process = nil
        lastTerminationStatus = nil
    }

    private func transportError(from error: any Error) -> any Error {
        if let hostError = error as? HostClientError {
            return hostError
        }

        if process?.isRunning != true {
            return HostClientError.hostExited(status: lastTerminationStatus)
        }

        return error
    }

    private func updateLifecycleIfNeeded(for error: any Error) {
        guard let hostError = error as? HostClientError,
            let status = hostError.connectionStatus
        else {
            return
        }

        updateLifecycle(status)
    }

    private func updateLifecycle(_ status: HostConnectionStatus) {
        guard lifecycleStatus != status else {
            return
        }

        lifecycleStatus = status
        let lifecycleHandler = self.lifecycleHandler
        Task { @MainActor in
            lifecycleHandler(status)
        }
    }

    private func failPendingResponses(with error: any Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
