import Foundation

/// The single entry point for runtime cycle execution.
/// Coordinates: decide → execute → commit → evaluate
public actor RuntimeOrchestrator: IntentAPI {
    private let container: RuntimeContainer
    private let eventStore: any EventStore
    private let commitCoordinator: CommitCoordinator
    private let planner: any Planner
    private let verifiedExecutor: VerifiedExecutor

    public init(container: RuntimeContainer) {
        self.container = container
        self.eventStore = container.eventStore
        self.commitCoordinator = container.commitCoordinator
        self.planner = container.planner
        self.verifiedExecutor = container.executor
    }

    private func evaluate(_ outcome: ExecutionOutcome) async -> EvaluationResult {
        let criticOutcome: CriticOutcome
        switch outcome.status {
        case .success:
            criticOutcome = .success
        case .partialSuccess:
            criticOutcome = .partialSuccess
        case .failed, .preconditionFailed, .postconditionFailed, .policyBlocked:
            criticOutcome = .failure
        }

        let needsRecovery = criticOutcome == .failure

        return EvaluationResult(
            commandID: outcome.commandID,
            criticOutcome: criticOutcome,
            needsRecovery: needsRecovery,
            notes: outcome.verifierReport.notes
        )
    }

    private func encodePayload<T: Encodable>(_ payload: T) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    private func makeIntentEvent(_ intent: Intent) throws -> EventEnvelope {
        EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: intent.id,
            eventType: "intent.received",
            payload: try encodePayload(
                IntentReceivedEvent(intentID: intent.id, objective: intent.objective)
            )
        )
    }

    private func makePlanEvent(intentID: UUID, command: Command) throws -> EventEnvelope {
        EventEnvelope(
            sequenceNumber: 0,
            commandID: command.id,
            intentID: intentID,
            eventType: "plan.generated",
            payload: try encodePayload(
                PlanGeneratedEvent(intentID: intentID, commandKind: command.kind)
            )
        )
    }

    private func makeEvaluationEvent(_ result: EvaluationResult, intentID: UUID?) throws -> EventEnvelope {
        EventEnvelope(
            sequenceNumber: 0,
            commandID: result.commandID,
            intentID: intentID,
            eventType: "evaluation.completed",
            payload: try encodePayload(
                EvaluationCompletedEvent(
                    commandID: result.commandID.uuidString,
                    criticOutcome: result.criticOutcome.rawValue,
                    needsRecovery: result.needsRecovery
                )
            )
        )
    }
}

extension RuntimeOrchestrator {
    public func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        let cycleID = UUID()
        var pendingEvents: [EventEnvelope] = []
        pendingEvents.append(try makeIntentEvent(intent))

        let command: Command
        do {
            let state = WorldStateModel(snapshot: await container.commitCoordinator.snapshot())
            command = try await container.planner.plan(intent: intent, state: state)
            pendingEvents.append(try makePlanEvent(intentID: intent.id, command: command))
        } catch {
            return IntentResponse(
                intentID: intent.id,
                outcome: .failed,
                summary: "Planning failed: \(error.localizedDescription)",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }

        let executionOutcome: ExecutionOutcome
        do {
            executionOutcome = try await container.executor.execute(command)
        } catch {
            executionOutcome = ExecutionOutcome.failure(from: error, command: command)
        }

        let evaluation = await evaluate(executionOutcome)
        pendingEvents.append(contentsOf: executionOutcome.events)
        pendingEvents.append(try makeEvaluationEvent(evaluation, intentID: intent.id))

        let receipt: CommitReceipt
        do {
            receipt = try await container.commitCoordinator.commit(pendingEvents)
        } catch {
            return IntentResponse(
                intentID: intent.id,
                outcome: .partialSuccess,
                summary: "Execution completed but commit failed: \(error.localizedDescription)",
                cycleID: cycleID,
                snapshotID: nil,
                timestamp: Date()
            )
        }

        let outcome: IntentResponse.Outcome
        switch executionOutcome.status {
        case .success:
            outcome = .success
        case .failed, .preconditionFailed, .postconditionFailed, .policyBlocked:
            outcome = .failed
        case .partialSuccess:
            outcome = .partialSuccess
        }

        return IntentResponse(
            intentID: intent.id,
            outcome: outcome,
            summary: "Intent completed: \(intent.objective) - \(executionOutcome.status.rawValue), critic=\(evaluation.criticOutcome.rawValue)",
            cycleID: cycleID,
            snapshotID: receipt.snapshotID,
            timestamp: receipt.timestamp
        )
    }

    public func queryState() async throws -> RuntimeSnapshot {
        let snapshot = await commitCoordinator.snapshot()

        let lastIntentID = snapshot.notes
            .last(where: { $0.hasPrefix("lastIntentID=") })
            .flatMap { UUID(uuidString: String($0.dropFirst("lastIntentID=".count))) }

        let lastCommandKind = snapshot.notes
            .last(where: { $0.hasPrefix("lastCommandKind=") })
            .map { String($0.dropFirst("lastCommandKind=".count)) }

        let appName = snapshot.activeApplication ?? "none"
        let recentNotes = snapshot.notes.suffix(3).joined(separator: " | ")

        return RuntimeSnapshot(
            id: UUID(),
            timestamp: snapshot.timestamp,
            cycleCount: snapshot.cycleCount,
            lastIntentID: lastIntentID,
            lastCommandKind: lastCommandKind,
            status: .idle,
            summary: "Runtime state: \(snapshot.visibleElementCount) visible elements, app: \(appName), notes: \(recentNotes)"
        )
    }
}
