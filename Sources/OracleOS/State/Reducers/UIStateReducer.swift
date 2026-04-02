import Foundation

public struct UIStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        for envelope in events {
            guard let event = DomainEventCodec.decode(from: envelope) else { continue }
            guard case .uiObserved(let payload) = event else { continue }

            state.update { snapshot in
                snapshot.copy(
                    activeApplication: .some(payload.activeApplication),
                    windowTitle: .some(payload.windowTitle),
                    url: .some(payload.url),
                    visibleElementCount: payload.visibleElementCount,
                    modalPresent: payload.modalPresent,
                    notes: Array((snapshot.notes + ["lastUIObservation=1"]).suffix(25))
                )
            }
        }
    }
}
