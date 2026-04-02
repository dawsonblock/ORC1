import Foundation

public enum DomainEvent: Sendable, Codable {
    case intentReceived(IntentReceivedEvent)
    case planGenerated(PlanGeneratedEvent)
    case commandExecuted(CommandExecutedEvent)
    case commandFailed(CommandFailedEvent)
    case evaluationCompleted(EvaluationCompletedEvent)
    case uiObserved(UIObservedEvent)
    case memoryRecorded(MemoryRecordedEvent)
    case fileModified(FileModifiedEvent)
}

public struct IntentReceivedEvent: Sendable, Codable {
    public let intentID: UUID
    public let objective: String
}

public struct PlanGeneratedEvent: Sendable, Codable {
    public let intentID: UUID?
    public let commandKind: String
}

public struct CommandExecutedEvent: Sendable, Codable {
    public let commandID: String
    public let commandKind: String
    public let status: String
    public let notes: [String]
}

public struct CommandFailedEvent: Sendable, Codable {
    public let commandID: String?
    public let commandKind: String?
    public let error: String
}

public struct EvaluationCompletedEvent: Sendable, Codable {
    public let commandID: String
    public let criticOutcome: String
    public let needsRecovery: Bool
}

public struct UIObservedEvent: Sendable, Codable {
    public let activeApplication: String?
    public let windowTitle: String?
    public let visibleElementCount: Int
    public let modalPresent: Bool
    public let url: String?
}

public struct MemoryRecordedEvent: Sendable, Codable {
    public let category: String
    public let key: String?
}

public struct FileModifiedEvent: Sendable, Codable {
    public let path: String
    public let operation: String
}

public enum DomainEventCodec {
    public static func decode(from envelope: EventEnvelope) -> DomainEvent? {
        let decoder = JSONDecoder()

        switch envelope.eventType {
        case "intent.received":
            guard let payload = try? decoder.decode(IntentReceivedEvent.self, from: envelope.payload) else { return nil }
            return .intentReceived(payload)

        case "plan.generated":
            guard let payload = try? decoder.decode(PlanGeneratedEvent.self, from: envelope.payload) else { return nil }
            return .planGenerated(payload)

        case "command.executed":
            guard let payload = try? decoder.decode(CommandExecutedEvent.self, from: envelope.payload) else { return nil }
            return .commandExecuted(payload)

        case "command.failed":
            guard let payload = try? decoder.decode(CommandFailedEvent.self, from: envelope.payload) else { return nil }
            return .commandFailed(payload)

        case "evaluation.completed":
            guard let payload = try? decoder.decode(EvaluationCompletedEvent.self, from: envelope.payload) else { return nil }
            return .evaluationCompleted(payload)

        case "ui.observed":
            guard let payload = try? decoder.decode(UIObservedEvent.self, from: envelope.payload) else { return nil }
            return .uiObserved(payload)

        case "memory.recorded":
            guard let payload = try? decoder.decode(MemoryRecordedEvent.self, from: envelope.payload) else { return nil }
            return .memoryRecorded(payload)

        case "file.modified":
            guard let payload = try? decoder.decode(FileModifiedEvent.self, from: envelope.payload) else { return nil }
            return .fileModified(payload)

        case "CommandSucceeded":
            let payload = (try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]) ?? [:]
            let status = payload["status"] as? String ?? "success"
            let commandKind = payload["commandKind"] as? String ?? "unknown"
            return .commandExecuted(
                CommandExecutedEvent(
                    commandID: envelope.commandID?.uuidString ?? "unknown",
                    commandKind: commandKind,
                    status: status,
                    notes: []
                )
            )

        case "CommandFailed":
            let payload = (try? JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]) ?? [:]
            let reason = (payload["reason"] as? String) ?? "unknown"
            let commandKind = payload["commandKind"] as? String
            return .commandFailed(
                CommandFailedEvent(
                    commandID: envelope.commandID?.uuidString,
                    commandKind: commandKind,
                    error: reason
                )
            )

        default:
            return nil
        }
    }
}
