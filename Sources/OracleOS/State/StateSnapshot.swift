import Foundation

/// Immutable snapshot of committed world state at a point in time.
/// INVARIANT: Snapshots are value types — they cannot mutate after creation.
public struct StateSnapshot: Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let sequenceNumber: Int
    public let state: WorldModelSnapshot
    public let eventAncestry: [UUID]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sequenceNumber: Int,
        state: WorldModelSnapshot,
        eventAncestry: [UUID]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.state = state
        self.eventAncestry = eventAncestry
    }
}
