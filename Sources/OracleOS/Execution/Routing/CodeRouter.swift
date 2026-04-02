import Foundation

public struct CodeRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?
    private let repositoryIndexer: RepositoryIndexer

    /// Truncate potentially large outputs before embedding them in observations
    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "\n...[truncated]"
    }

    init(
        workspaceRunner: WorkspaceRunner?,
        repositoryIndexer: RepositoryIndexer
    ) {
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        guard command.type == .code else {
            throw RouterError.invalidRoute(expected: .code, actual: command.type)
        }

        switch command.payload {
        case .build(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            let result = try await workspaceRunner.runBuild(spec)
            let observations = buildObservations(result)
            
            if result.exitCode == 0 {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, limit: 2000),
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

        case .test(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            let result = try await workspaceRunner.runTest(spec)
            let observations = buildObservations(result)
            
            if result.exitCode == 0 {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, limit: 2000),
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

        case .git(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            let result = try await workspaceRunner.runGit(spec)
            let observations = buildObservations(result)
            
            if result.exitCode == 0 {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, limit: 2000),
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

        case .file(let spec):
            do {
                try await workspaceRunner?.applyFile(spec)
                let fileEvent = DomainEventFactory.fileModified(
                    path: spec.path,
                    operation: spec.operation.rawValue,
                    commandID: command.id,
                    intentID: command.metadata.intentID
                )
                return CommandRouter.successOutcome(
                    command: command,
                    observations: [
                        ObservationPayload(
                            kind: "fileModified",
                            content: "File operation: \(spec.operation.rawValue) on \(spec.path)"
                        )
                    ],
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code",
                    additionalEvents: [fileEvent]
                )
            } catch {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "File operation failed: \(error.localizedDescription)",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

        case .code(let action):
            return try executeCodeAction(
                action,
                command: command,
                policyDecision: policyDecision
            )

        
        

case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid code payload",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func buildObservations(_ result: ProcessResult) -> [ObservationPayload] {
        let maxLogLength = 2000
        let truncatedStdout = truncated(result.stdout, limit: maxLogLength)
        let truncatedStderr = truncated(result.stderr, limit: maxLogLength)
        
        return [
            ObservationPayload(
                kind: "code.execution",
                content: "Exit code: \(result.exitCode), Duration: \(Int(result.durationMs))ms\nStdout:\n\(truncatedStdout)\nStderr:\n\(truncatedStderr)"
            )
        ]
    }

    private func executeCodeAction(
        _ action: CodeAction,
        command: Command,
        policyDecision: PolicyDecision
    ) throws -> ExecutionOutcome {
        switch action.name {
        case "searchRepository":
            let workspaceRoot = action.workspacePath ?? FileManager.default.currentDirectoryPath
            let snapshot = repositoryIndexer.indexIfNeeded(
                workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            )
            let matches = CodeSearch().search(query: action.query ?? "", in: snapshot)
            let content = matches
                .prefix(10)
                .map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }
                .joined(separator: "\n")
            return CommandRouter.successOutcome(
                command: command,
                observations: [
                    ObservationPayload(
                        kind: "searchResult",
                        content: content.isEmpty ? "no matches" : content
                    ),
                ],
                artifacts: [],
                policyDecision: policyDecision,
                router: "code"
            )

        case "readFile":
            guard let resolvedPath = try resolvePath(filePath: action.filePath, workspacePath: action.workspacePath),
                  let data = FileManager.default.contents(atPath: resolvedPath.path),
                  let text = String(data: data, encoding: .utf8)
            else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Unable to read \(action.filePath ?? "file")",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }
            return CommandRouter.successOutcome(
                command: command,
                observations: [ObservationPayload(kind: "fileContent", content: text)],
                artifacts: [ArtifactPayload(kind: "file", identifier: resolvedPath.path, data: data)],
                policyDecision: policyDecision,
                router: "code"
            )

        default:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Unsupported code action: \(action.name)",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func resolvePath(filePath: String?, workspacePath: String?) throws -> URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        guard let workspacePath, !filePath.hasPrefix("/") else {
            return URL(fileURLWithPath: filePath)
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: workspacePath, isDirectory: true))
        return try scope.resolve(relativePath: filePath)
    }
}
