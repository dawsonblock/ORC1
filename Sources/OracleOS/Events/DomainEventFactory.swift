import Foundation

/// Canonical factory for domain events.
/// All runtime event producers must use this factory to ensure consistent event schema.
public enum DomainEventFactory {

    // MARK: - Command Events

    public static func commandExecuted(
        command: Command,
        status: String = "success",
        notes: [String] = []
    ) -> EventEnvelope {
        let payload = CommandExecutedEvent(
            commandID: command.id.uuidString,
            commandKind: command.kind,
            status: status,
            notes: notes
        )
        return encode(
            eventType: "command.executed",
            payload: payload,
            commandID: command.id,
            intentID: command.metadata.intentID
        )
    }

    public static func commandFailed(
        command: Command,
        error: String
    ) -> EventEnvelope {
        let payload = CommandFailedEvent(
            commandID: command.id.uuidString,
            commandKind: command.kind,
            error: error
        )
        return encode(
            eventType: "command.failed",
            payload: payload,
            commandID: command.id,
            intentID: command.metadata.intentID
        )
    }

    // MARK: - Planning Events

    public static func planGenerated(
        intentID: UUID?,
        commandKind: String,
        command: Command? = nil
    ) -> EventEnvelope {
        let payload = PlanGeneratedEvent(intentID: intentID, commandKind: commandKind)
        return encode(
            eventType: "plan.generated",
            payload: payload,
            commandID: command?.id,
            intentID: intentID
        )
    }

    public static func intentReceived(
        intentID: UUID,
        objective: String
    ) -> EventEnvelope {
        let payload = IntentReceivedEvent(intentID: intentID, objective: objective)
        return encode(
            eventType: "intent.received",
            payload: payload,
            intentID: intentID
        )
    }

    // MARK: - Evaluation Events

    public static func evaluationCompleted(
        commandID: UUID,
        intentID: UUID?,
        criticOutcome: String,
        needsRecovery: Bool
    ) -> EventEnvelope {
        let payload = EvaluationCompletedEvent(
            commandID: commandID.uuidString,
            criticOutcome: criticOutcome,
            needsRecovery: needsRecovery
        )
        return encode(
            eventType: "evaluation.completed",
            payload: payload,
            commandID: commandID,
            intentID: intentID
        )
    }

    // MARK: - UI Events

    public static func uiObserved(
        activeApplication: String?,
        windowTitle: String?,
        visibleElementCount: Int,
        modalPresent: Bool,
        url: String?,
        commandID: UUID? = nil,
        intentID: UUID? = nil
    ) -> EventEnvelope {
        let payload = UIObservedEvent(
            activeApplication: activeApplication,
            windowTitle: windowTitle,
            visibleElementCount: visibleElementCount,
            modalPresent: modalPresent,
            url: url
        )
        return encode(
            eventType: "ui.observed",
            payload: payload,
            commandID: commandID,
            intentID: intentID
        )
    }

    // MARK: - Memory Events

    public static func memoryRecorded(
        category: String,
        key: String?,
        commandID: UUID? = nil,
        intentID: UUID? = nil
    ) -> EventEnvelope {
        let payload = MemoryRecordedEvent(category: category, key: key)
        return encode(
            eventType: "memory.recorded",
            payload: payload,
            commandID: commandID,
            intentID: intentID
        )
    }

    // MARK: - File Events

    public static func fileModified(
        path: String,
        operation: String,
        commandID: UUID? = nil,
        intentID: UUID? = nil
    ) -> EventEnvelope {
        let payload = FileModifiedEvent(path: path, operation: operation)
        return encode(
            eventType: "file.modified",
            payload: payload,
            commandID: commandID,
            intentID: intentID
        )
    }

    // MARK: - Private Encoding

    private static func encode<T: Encodable>(
        eventType: String,
        payload: T,
        commandID: UUID? = nil,
        intentID: UUID? = nil
    ) -> EventEnvelope {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return EventEnvelope(
            sequenceNumber: 0, // Will be assigned by CommitCoordinator
            commandID: commandID,
            intentID: intentID,
            timestamp: Date(),
            eventType: eventType,
            payload: data
        )
    }
}
