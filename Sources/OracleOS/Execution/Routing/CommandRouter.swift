import Foundation

public struct CommandRouter: @unchecked Sendable {
    private let systemRouter: SystemRouter
    private let uiRouter: UIRouter
    private let codeRouter: CodeRouter

    public init(
        automationHost: AutomationHost? = nil,
        workspaceRunner: WorkspaceRunner? = nil,
        repositoryIndexer: RepositoryIndexer
    ) {
        self.systemRouter = SystemRouter(workspaceRunner: workspaceRunner)
        self.uiRouter = UIRouter(automationHost: automationHost)
        self.codeRouter = CodeRouter(
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer
        )
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        switch command.type {
        case .system:
            return try await systemRouter.execute(command, policyDecision: policyDecision)
        case .ui:
            return try await uiRouter.execute(command, policyDecision: policyDecision)
        case .code:
            return try await codeRouter.execute(command, policyDecision: policyDecision)
        }
    }

    public static func domain(for command: Command) -> CommandType {
        command.type
    }

    static func successOutcome(
        command: Command,
        observations: [ObservationPayload],
        artifacts: [ArtifactPayload],
        policyDecision: PolicyDecision,
        router: String,
        additionalEvents: [EventEnvelope] = []
    ) -> ExecutionOutcome {
        let event = DomainEventFactory.commandExecuted(
            command: command,
            status: "success",
            notes: ["router: \(router)"]
        )
        return ExecutionOutcome(
            commandID: command.id,
            status: .success,
            observations: observations,
            artifacts: artifacts,
            events: [event] + additionalEvents,
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: policyDecision.allowed ? "approved" : "blocked",
                postconditionsPassed: true
            )
        )
    }

    static func failureOutcome(
        command: Command,
        reason: String,
        policyDecision: PolicyDecision,
        router: String,
        status: ExecutionStatus = .failed
    ) -> ExecutionOutcome {
        let event = DomainEventFactory.commandFailed(
            command: command,
            error: "\(reason) (router: \(router))"
        )
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: [event],
            verifierReport: VerifierReport(
                commandID: command.id,
                preconditionsPassed: true,
                policyDecision: policyDecision.allowed ? "approved" : "blocked",
                postconditionsPassed: false,
                notes: [reason]
            )
        )
    }
}
