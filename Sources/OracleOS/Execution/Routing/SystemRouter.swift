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
        case .build:
            // Build commands must use command.type == .code and route through CodeRouter.
            // All planners emit CommandType.code for build; reaching this case indicates
            // a misconfigured command source.
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Build commands must use command.type == .code and route through CodeRouter, not SystemRouter",
                policyDecision: policyDecision,
                router: "system"
            )

        case .test:
            // Test commands must use command.type == .code and route through CodeRouter.
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Test commands must use command.type == .code and route through CodeRouter, not SystemRouter",
                policyDecision: policyDecision,
                router: "system"
            )

        case .git:
            // Git commands must use command.type == .code and route through CodeRouter.
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Git commands must use command.type == .code and route through CodeRouter, not SystemRouter",
                policyDecision: policyDecision,
                router: "system"
            )

        case .file:
            // File mutations are exclusively handled by CodeRouter via command.type == .code.
            // A system command must never carry a .file payload — routing table is broken
            // upstream if this case is reached.
            return CommandRouter.failureOutcome(
                command: command,
                reason: "File mutations must be routed as code commands (command.type == .code), not system commands",
                policyDecision: policyDecision,
                router: "system"
            )

        
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
