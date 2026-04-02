import Foundation

public struct ProjectStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        for envelope in events {
            guard let event = DomainEventCodec.decode(from: envelope) else { continue }

            switch event {
            case .commandExecuted(let payload):
                let kind = payload.commandKind.lowercased()
                state.update { snapshot in
                    var buildSucceeded = snapshot.buildSucceeded
                    var failingTestCount = snapshot.failingTestCount
                    var notes = snapshot.notes

                    if kind.contains("build") {
                        buildSucceeded = payload.status == "success"
                    }
                    if kind.contains("test") {
                        if payload.status == "success" { failingTestCount = 0 }
                        notes.append("lastProjectCommand=\(payload.commandKind)")
                    }

                    return snapshot.copy(
                        buildSucceeded: .some(buildSucceeded),
                        failingTestCount: .some(failingTestCount),
                        notes: Array(notes.suffix(25))
                    )
                }

            case .commandFailed(let payload):
                let kind = payload.commandKind?.lowercased() ?? ""
                state.update { snapshot in
                    var notes = snapshot.notes
                    var buildSucceeded = snapshot.buildSucceeded
                    
                    if kind.contains("build") {
                        buildSucceeded = false
                    }
                    notes.append("lastProjectCommandFailed=\(payload.commandKind ?? "unknown")")

                    return snapshot.copy(
                        buildSucceeded: .some(buildSucceeded),
                        notes: Array(notes.suffix(25))
                    )
                }

            case .fileModified(let payload):
                state.update { snapshot in
                    var notes = snapshot.notes
                    notes.append("fileModified=\(payload.operation):\(payload.path)")
                    return snapshot.copy(notes: Array(notes.suffix(25)))
                }

            default:
                break
            }
        }
    }
}
