import Foundation

public struct SystemRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?

    init(workspaceRunner: WorkspaceRunner?) {
        self.workspaceRunner = workspaceRunner
    }

    /// Truncate potentially large command output before including it in observations.
    private func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<endIndex]) + "\n... [output truncated]"
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        guard command.type == .system else {
            throw RouterError.invalidRoute(expected: .system, actual: command.type)
        }

        switch command.payload {
        case .build(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "system"
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
                    router: "system"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, maxLength: 2000),
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

        case .test(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "system"
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
                    router: "system"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, maxLength: 2000),
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

        case .git(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "system"
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
                    router: "system"
                )
            } else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: truncated(result.stderr, maxLength: 2000),
                    policyDecision: policyDecision,
                    router: "system"
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
                    router: "system",
                    additionalEvents: [fileEvent]
                )
            } catch {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "File operation failed: \(error.localizedDescription)",
                    policyDecision: policyDecision,
                    router: "system"
                )
            }

        
case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload: received UI action for system command",
                policyDecision: policyDecision,
                router: "system"
            )

        case .code:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid system payload: received code action for system command",
                policyDecision: policyDecision,
                router: "system"
            )
        }
    }

    private func buildObservations(_ result: ProcessResult) -> [ObservationPayload] {
        let maxLength = 2000
        return [
            ObservationPayload(
                kind: "system.execution",
                content: """
                Exit code: \(result.exitCode), Duration: \(Int(result.durationMs))ms
                Stdout:
                \(truncated(result.stdout, maxLength: maxLength))
                Stderr:
                \(truncated(result.stderr, maxLength: maxLength))
                """
            ),
        ]
    }
}
