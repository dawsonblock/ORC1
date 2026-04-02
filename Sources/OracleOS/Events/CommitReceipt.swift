import Foundation

public struct CommitReceipt: Sendable, Codable {
    public let commitID: UUID
    public let timestamp: Date
    public let firstSequenceNumber: Int
    public let lastSequenceNumber: Int
    public let eventIDs: [UUID]
    public let snapshotID: UUID
    public let summary: String

    public init(
        commitID: UUID = UUID(),
        timestamp: Date = Date(),
        firstSequenceNumber: Int,
        lastSequenceNumber: Int,
        eventIDs: [UUID],
        snapshotID: UUID,
        summary: String
    ) {
        self.commitID = commitID
        self.timestamp = timestamp
        self.firstSequenceNumber = firstSequenceNumber
        self.lastSequenceNumber = lastSequenceNumber
        self.eventIDs = eventIDs
        self.snapshotID = snapshotID
        self.summary = summary
    }
}

public enum CommitError: Error {
    case emptyCommit
}
