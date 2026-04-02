import Foundation

/// Append-only event log. The single source of truth for all state changes.
/// INVARIANT: Events are never deleted or mutated after append.
public protocol EventStore: Actor {
    func append(_ envelope: EventEnvelope) throws
    func append(contentsOf newEnvelopes: [EventEnvelope]) throws
    func all() throws -> [EventEnvelope]
    func events(forCommandID id: CommandID) throws -> [EventEnvelope]
    func events(after sequenceNumber: Int) throws -> [EventEnvelope]
    func nextSequenceNumber() throws -> Int
}

public actor MemoryEventStore: EventStore {
    private var envelopes: [EventEnvelope] = []
    private var sequenceCounter: Int = 0

    public init() {}

    public func append(_ envelope: EventEnvelope) {
        envelopes.append(envelope)
    }

    public func append(contentsOf newEnvelopes: [EventEnvelope]) {
        envelopes.append(contentsOf: newEnvelopes)
    }

    public func all() -> [EventEnvelope] { envelopes }

    public func events(forCommandID id: CommandID) -> [EventEnvelope] {
        envelopes.filter { $0.commandID == id }
    }

    public func events(after sequenceNumber: Int) -> [EventEnvelope] {
        envelopes.filter { $0.sequenceNumber > sequenceNumber }
    }

    public func nextSequenceNumber() -> Int {
        sequenceCounter += 1
        return sequenceCounter
    }
}

