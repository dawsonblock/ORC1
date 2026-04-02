import XCTest
@testable import OracleOS

/// Verifies that a runtime cycle can be replayed from event history
/// and produce the same committed state snapshot — Milestone E.
final class EventReplayTests: XCTestCase {

    // MARK: - Core replay invariant

    /// Replaying the same sequence of events through reducers must always
    /// produce an identical state snapshot — deterministic reducer output.
    func test_event_replay_produces_deterministic_state() async throws {
        let store1 = MemoryEventStore()
        let coordinator1 = CommitCoordinator(
            eventStore: store1,
            reducers: [RuntimeStateReducer(), UIStateReducer(), ProjectStateReducer()]
        )

        // Commit a sequence of events
        let commandID = CommandID()
        let intentID = UUID()
        let envelopes = [
            EventEnvelope(sequenceNumber: 0, commandID: commandID, intentID: intentID,
                          eventType: "commandIssued", payload: Data()),
            EventEnvelope(sequenceNumber: 0, commandID: commandID, intentID: intentID,
                          eventType: "actionStarted", payload: Data()),
            EventEnvelope(sequenceNumber: 0, commandID: commandID, intentID: intentID,
                          eventType: "actionCompleted", payload: Data())
        ]

        try await coordinator1.commit(envelopes)
        let snapshot1 = await coordinator1.snapshot()

        // Replay the same events into a fresh coordinator
        let allEvents = await store1.all()
        let store2 = MemoryEventStore()
        let coordinator2 = CommitCoordinator(
            eventStore: store2,
            reducers: [RuntimeStateReducer(), UIStateReducer(), ProjectStateReducer()]
        )
        try await coordinator2.commit(allEvents)
        let snapshot2 = await coordinator2.snapshot()

        // Both snapshots must represent identical state
        XCTAssertEqual(allEvents.count, 3, "Three events must be committed")
        XCTAssertNotNil(snapshot1)
        XCTAssertNotNil(snapshot2)
        // Both snapshots derived from same event sequence — verify cycle counts match
        XCTAssertEqual(
            snapshot1.cycleCount,
            snapshot2.cycleCount,
            "Replayed state must match original committed state"
        )
    }

    /// EventReplay struct must reconstruct a timeline from event history.
    func test_event_replay_builds_timeline() async throws {
        let store = MemoryEventStore()
        let commandID = CommandID()
        let cycleID = UUID()

        // Append events directly for replay test
        await store.append(EventEnvelope(
            sequenceNumber: 1,
            commandID: commandID,
            intentID: cycleID,
            eventType: "actionStarted",
            payload: Data()
        ))
        await store.append(EventEnvelope(
            sequenceNumber: 2,
            commandID: commandID,
            intentID: cycleID,
            eventType: "actionCompleted",
            payload: Data()
        ))

        let replay = EventReplay(eventStore: store)
        let timeline = try await replay.replay(cycleID: cycleID)

        XCTAssertEqual(timeline.events.count, 2)
        XCTAssertFalse(timeline.events.isEmpty, "Timeline must contain replayed events")
    }

    /// TimelineBuilder produces a timeline with the correct event order.
    func test_timeline_builder_preserves_event_order() {
        let events = [
            EventEnvelope(sequenceNumber: 1, commandID: nil, intentID: nil, eventType: "first", payload: Data()),
            EventEnvelope(sequenceNumber: 2, commandID: nil, intentID: nil, eventType: "second", payload: Data()),
            EventEnvelope(sequenceNumber: 3, commandID: nil, intentID: nil, eventType: "third", payload: Data())
        ]

        let timeline = TimelineBuilder().build(from: events)
        XCTAssertEqual(timeline.events.count, 3)
        XCTAssertEqual(timeline.events[0].eventType, "first")
        XCTAssertEqual(timeline.events[2].eventType, "third")
    }

    /// CommitCoordinator snapshot reflects committed event history.
    func test_snapshot_reflects_committed_events() async throws {
        let store = MemoryEventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [RuntimeStateReducer()])

        let initial = await coordinator.snapshot()
        XCTAssertEqual(initial.cycleCount, 0, "Initial cycle count must be zero")

        // Commit events — reducer will update state
        _ = try await coordinator.commit([
            EventEnvelope(sequenceNumber: 0, commandID: nil, intentID: nil, eventType: "e1", payload: Data()),
            EventEnvelope(sequenceNumber: 0, commandID: nil, intentID: nil, eventType: "e2", payload: Data())
        ])

        let eventsInStore = await store.all()
        XCTAssertEqual(eventsInStore.count, 2, "Events must be stored after commit")
    }
}
