// MARK: - IntentResponse
// Oracle-OS vNext — Response returned to the controller after an intent cycle completes.

import Foundation

public struct IntentResponse: Sendable, Codable {
    public enum Outcome: String, Sendable, Codable {
        case success
        case failed
        case partialSuccess
        case skipped
    }

    public let intentID: UUID
    public let outcome: Outcome
    public let summary: String
    public let cycleID: UUID
    public let snapshotID: UUID?
    public let timestamp: Date
    /// Non-nil when the outcome is `failed` due to a required approval.
    /// Callers must re-submit with this ID as the `approvalToken` after the user approves.
    public let approvalRequestID: String?
    /// "pending" when an approval request was created. Nil otherwise.
    public let approvalStatus: String?

    public init(
        intentID: UUID,
        outcome: Outcome,
        summary: String,
        cycleID: UUID,
        snapshotID: UUID? = nil,
        timestamp: Date = Date(),
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil
    ) {
        self.intentID = intentID
        self.outcome = outcome
        self.summary = summary
        self.cycleID = cycleID
        self.snapshotID = snapshotID
        self.timestamp = timestamp
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
    }
}
