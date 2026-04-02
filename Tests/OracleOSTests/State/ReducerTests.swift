import Foundation
import Testing
@testable import OracleOS

struct ReducerTests {
    @Test func runtimeReducerIncrementsCycleCountAndTracksIntent() {
        var model = WorldStateModel()
        let reducer = RuntimeStateReducer()

        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: UUID(uuidString: "00000000-0000-0000-0000-000000000111"),
            eventType: "intent.received",
            payload: try! JSONEncoder().encode(
                IntentReceivedEvent(
                    intentID: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
                    objective: "open safari"
                )
            )
        )

        reducer.apply(events: [event], to: &model)

        #expect(model.snapshot.cycleCount == 1)
        #expect(model.snapshot.notes.contains(where: { $0.contains("lastIntentID=") }))
    }

    @Test func uiReducerUpdatesVisibleUiState() {
        var model = WorldStateModel()
        let reducer = UIStateReducer()

        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: nil,
            eventType: "ui.observed",
            payload: try! JSONEncoder().encode(
                UIObservedEvent(
                    activeApplication: "Safari",
                    windowTitle: "Example",
                    visibleElementCount: 7,
                    modalPresent: false,
                    url: "https://example.com"
                )
            )
        )

        reducer.apply(events: [event], to: &model)

        #expect(model.snapshot.activeApplication == "Safari")
        #expect(model.snapshot.windowTitle == "Example")
        #expect(model.snapshot.visibleElementCount == 7)
    }

    @Test func projectReducerTracksBuildSuccess() {
        var model = WorldStateModel()
        let reducer = ProjectStateReducer()

        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: UUID(),
            intentID: UUID(),
            eventType: "command.executed",
            payload: try! JSONEncoder().encode(
                CommandExecutedEvent(
                    commandID: UUID().uuidString,
                    commandKind: "build",
                    status: "success",
                    notes: []
                )
            )
        )

        reducer.apply(events: [event], to: &model)

        #expect(model.snapshot.buildSucceeded == true)
    }

    @Test func memoryReducerTracksKnowledgeSignals() {
        var model = WorldStateModel()
        let reducer = MemoryStateReducer()

        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: nil,
            eventType: "memory.recorded",
            payload: try! JSONEncoder().encode(
                MemoryRecordedEvent(category: "project", key: "repo-root")
            )
        )

        reducer.apply(events: [event], to: &model)

        #expect(model.snapshot.knowledgeSignals.contains("project"))
    }
}