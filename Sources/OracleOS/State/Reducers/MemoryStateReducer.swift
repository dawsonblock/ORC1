import Foundation

public struct MemoryStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        for envelope in events {
            guard let event = DomainEventCodec.decode(from: envelope) else { continue }
            guard case .memoryRecorded(let payload) = event else { continue }

            state.update { snapshot in
                // Idempotent: don't add if already present
                let newSignal = payload.category
                let newNote = "lastMemoryKey=\(payload.key ?? "unknown")"
                guard !snapshot.knowledgeSignals.contains(newSignal) || !snapshot.notes.contains(newNote) else {
                    return snapshot
                }
                var signals = snapshot.knowledgeSignals
                var notes = snapshot.notes
                if !signals.contains(newSignal) {
                    signals.append(newSignal)
                }
                if !notes.contains(newNote) {
                    notes.append(newNote)
                }
                return snapshot.copy(
                    knowledgeSignals: Array(signals.suffix(20)),
                    notes: Array(notes.suffix(25))
                )
            }
        }
    }
}
