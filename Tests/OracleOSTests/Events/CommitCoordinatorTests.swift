import Foundation
import Testing
@testable import OracleOS

struct CommitCoordinatorTests {
    @Test func commitReturnsReceiptAndRunsReducers() async throws {
        let store = MemoryEventStore()
        let reducer = CompositeStateReducer(reducers: [RuntimeStateReducer()])
        let coordinator = CommitCoordinator(eventStore: store, reducers: [reducer])

        let intentID = UUID()
        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: intentID,
            eventType: "intent.received",
            payload: try JSONEncoder().encode(
                IntentReceivedEvent(intentID: intentID, objective: "open safari")
            )
        )

        let receipt = try await coordinator.commit([event])
        let snapshot = await coordinator.snapshot()

        #expect(receipt.firstSequenceNumber == 1)
        #expect(receipt.lastSequenceNumber == 1)
        #expect(!receipt.eventIDs.isEmpty)
        #expect(snapshot.cycleCount == 1)
    }

    @Test func emptyCommitThrows() async {
        let store = MemoryEventStore()
        let reducer = CompositeStateReducer(reducers: [RuntimeStateReducer()])
        let coordinator = CommitCoordinator(eventStore: store, reducers: [reducer])

        await #expect(throws: CommitError.self) {
            _ = try await coordinator.commit([])
        }
    }
}
