import Foundation

public struct RuntimeStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        for envelope in events {
            guard let event = DomainEventCodec.decode(from: envelope) else { continue }

            state.update { snapshot in
                switch event {
                case .intentReceived(let payload):
                    let newNote = "lastIntentID=\(payload.intentID.uuidString)"
                    guard !snapshot.notes.contains(newNote) else { return snapshot }
                    return snapshot.copy(
                        cycleCount: snapshot.cycleCount + 1,
                        notes: Array((snapshot.notes + [newNote]).suffix(25))
                    )

                case .planGenerated(let payload):
                    let newNote = "lastCommandKind=\(payload.commandKind)"
                    guard !snapshot.notes.contains(newNote) else { return snapshot }
                    return snapshot.copy(
                        notes: Array((snapshot.notes + [newNote]).suffix(25))
                    )

                case .commandExecuted(let payload):
                    let newNote = "lastExecutionStatus=\(payload.status)"
                    guard !snapshot.notes.contains(newNote) else { return snapshot }
                    return snapshot.copy(
                        notes: Array((snapshot.notes + [newNote] + payload.notes.prefix(3)).suffix(25))
                    )

                case .commandFailed(let payload):
                    var notes = snapshot.notes
                    let failureNote = "lastFailure=\(payload.error)"
                    if !notes.contains(failureNote) {
                        notes.append(failureNote)
                    }
                    if let kind = payload.commandKind {
                        let kindNote = "lastCommandKind=\(kind)"
                        if !notes.contains(kindNote) {
                            notes.append(kindNote)
                        }
                    }
                    return snapshot.copy(notes: Array(notes.suffix(25)))

                case .evaluationCompleted(let payload):
                    let newNote = "criticOutcome=\(payload.criticOutcome)"
                    guard !snapshot.notes.contains(newNote) else { return snapshot }
                    return snapshot.copy(
                        notes: Array((snapshot.notes + [newNote]).suffix(25))
                    )

                default:
                    return snapshot
                }
            }
        }
    }
}
