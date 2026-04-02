import Foundation
/// Composite reducer — applies all sub-reducers in order.
public struct CompositeStateReducer: EventReducer {
    private let reducers: [any EventReducer]
    public init(reducers: [any EventReducer]) { self.reducers = reducers }
    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        for reducer in reducers { reducer.apply(events: events, to: &state) }
    }
}
