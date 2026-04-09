import Foundation
import Testing
@testable import OracleOS

// MARK: - ActionTrace Tests

@Suite("ActionTrace")
struct ActionTraceTests {

    private func makeEnvelope(
        seq: Int,
        commandID: CommandID,
        intentID: UUID,
        eventType: String,
        timestamp: Date = Date()
    ) -> EventEnvelope {
        EventEnvelope(
            sequenceNumber: seq,
            commandID: commandID,
            intentID: intentID,
            timestamp: timestamp,
            eventType: eventType,
            payload: Data()
        )
    }

    @Test("Direct init captures all fields")
    func initCapturesFields() {
        let commandID = CommandID()
        let intentID = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_005)
        let trace = ActionTrace(
            commandID: commandID,
            intentID: intentID,
            startTime: start,
            endTime: end,
            domain: "code",
            outcome: "completed",
            eventCount: 3
        )
        #expect(trace.commandID == commandID)
        #expect(trace.intentID == intentID)
        #expect(trace.startTime == start)
        #expect(trace.endTime == end)
        #expect(trace.domain == "code")
        #expect(trace.outcome == "completed")
        #expect(trace.eventCount == 3)
    }

    @Test("Duration is nil when endTime is absent")
    func durationNilWithoutEndTime() {
        let trace = ActionTrace(
            commandID: CommandID(),
            intentID: UUID(),
            startTime: Date(),
            endTime: nil,
            domain: "ui"
        )
        #expect(trace.duration == nil)
    }

    @Test("Duration computed correctly from start and end")
    func durationComputed() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_007)
        let trace = ActionTrace(
            commandID: CommandID(),
            intentID: UUID(),
            startTime: start,
            endTime: end,
            domain: "ui"
        )
        #expect(trace.duration == 7)
    }

    @Test("Factory returns nil when event list is empty")
    func factoryReturnsNilForEmptyEvents() {
        let result = ActionTrace.from(events: [], domain: "ui")
        #expect(result == nil)
    }

    @Test("Factory builds trace from completed events")
    func factoryBuildsCompletedTrace() {
        let commandID = CommandID()
        let intentID = UUID()
        let t0 = Date(timeIntervalSince1970: 100)
        let t1 = Date(timeIntervalSince1970: 105)
        let events = [
            makeEnvelope(seq: 1, commandID: commandID, intentID: intentID, eventType: "actionStarted", timestamp: t0),
            makeEnvelope(seq: 2, commandID: commandID, intentID: intentID, eventType: "actionCompleted", timestamp: t1),
        ]
        let trace = ActionTrace.from(events: events, domain: "code")
        #expect(trace != nil)
        #expect(trace?.outcome == "completed")
        #expect(trace?.eventCount == 2)
        #expect(trace?.domain == "code")
        #expect(trace?.commandID == commandID)
        #expect(trace?.intentID == intentID)
    }

    @Test("Factory marks outcome as failed when actionFailed event present")
    func factoryBuildsFailedTrace() {
        let commandID = CommandID()
        let intentID = UUID()
        let events = [
            makeEnvelope(seq: 1, commandID: commandID, intentID: intentID, eventType: "actionStarted"),
            makeEnvelope(seq: 2, commandID: commandID, intentID: intentID, eventType: "actionFailed"),
        ]
        let trace = ActionTrace.from(events: events, domain: "ui")
        #expect(trace?.outcome == "failed")
    }

    @Test("Factory marks outcome as unknown when no terminal event present")
    func factoryBuildsUnknownOutcomeTrace() {
        let commandID = CommandID()
        let intentID = UUID()
        let events = [
            makeEnvelope(seq: 1, commandID: commandID, intentID: intentID, eventType: "actionStarted"),
        ]
        let trace = ActionTrace.from(events: events, domain: "ui")
        #expect(trace?.outcome == "unknown")
    }

    @Test("Factory picks earliest timestamp as startTime")
    func factoryPicksEarliestStart() {
        let commandID = CommandID()
        let intentID = UUID()
        let t0 = Date(timeIntervalSince1970: 50)
        let t1 = Date(timeIntervalSince1970: 200)
        let events = [
            makeEnvelope(seq: 2, commandID: commandID, intentID: intentID, eventType: "actionCompleted", timestamp: t1),
            makeEnvelope(seq: 1, commandID: commandID, intentID: intentID, eventType: "actionStarted", timestamp: t0),
        ]
        let trace = ActionTrace.from(events: events, domain: "ui")
        #expect(trace?.startTime == t0)
    }
}

// MARK: - DecisionTrace Tests

@Suite("DecisionTrace")
struct DecisionTraceTests {

    @Test("Init captures all fields")
    func initCapturesFields() {
        let intentID = UUID()
        let ts = Date(timeIntervalSince1970: 42)
        let trace = DecisionTrace(intentID: intentID, strategy: "depth-first", confidence: 0.85, timestamp: ts)
        #expect(trace.intentID == intentID)
        #expect(trace.strategy == "depth-first")
        #expect(trace.confidence == 0.85)
        #expect(trace.timestamp == ts)
    }

    @Test("Default timestamp is close to now")
    func defaultTimestampIsNow() {
        let before = Date()
        let trace = DecisionTrace(intentID: UUID(), strategy: "beam", confidence: 0.5)
        let after = Date()
        #expect(trace.timestamp >= before)
        #expect(trace.timestamp <= after)
    }
}

// MARK: - ExecutionTrace Tests

@Suite("ExecutionTrace")
struct ExecutionTraceTests {

    @Test("Init captures all fields")
    func initCapturesFields() {
        let commandID = CommandID()
        let ts = Date(timeIntervalSince1970: 99)
        let trace = ExecutionTrace(
            commandID: commandID,
            preconditionsPassed: true,
            postconditionsPassed: false,
            status: .failed,
            timestamp: ts
        )
        #expect(trace.commandID == commandID)
        #expect(trace.preconditionsPassed == true)
        #expect(trace.postconditionsPassed == false)
        #expect(trace.status == .failed)
        #expect(trace.timestamp == ts)
    }

    @Test("Default timestamp is close to now")
    func defaultTimestampIsNow() {
        let before = Date()
        let trace = ExecutionTrace(
            commandID: CommandID(),
            preconditionsPassed: true,
            postconditionsPassed: true,
            status: .success
        )
        let after = Date()
        #expect(trace.timestamp >= before)
        #expect(trace.timestamp <= after)
    }
}

// MARK: - PlanTrace Tests

@Suite("PlanTrace")
struct PlanTraceTests {

    @Test("Init captures all fields including planning steps")
    func initCapturesFields() {
        let intentID = UUID()
        let commandID = CommandID()
        let steps = ["analyze", "patch", "verify"]
        let ts = Date(timeIntervalSince1970: 500)
        let trace = PlanTrace(intentID: intentID, commandID: commandID, planningSteps: steps, timestamp: ts)
        #expect(trace.intentID == intentID)
        #expect(trace.commandID == commandID)
        #expect(trace.planningSteps == steps)
        #expect(trace.timestamp == ts)
    }

    @Test("Empty planning steps are accepted")
    func emptyStepsAccepted() {
        let trace = PlanTrace(intentID: UUID(), commandID: CommandID(), planningSteps: [])
        #expect(trace.planningSteps.isEmpty)
    }
}

// MARK: - TimelineBuilder Tests

@Suite("TimelineBuilder")
struct TimelineBuilderTests {

    private func makeEnvelope(seq: Int, eventType: String, timestamp: Date = Date()) -> EventEnvelope {
        EventEnvelope(
            sequenceNumber: seq,
            commandID: nil,
            intentID: nil,
            timestamp: timestamp,
            eventType: eventType,
            payload: Data()
        )
    }

    @Test("Empty event list produces empty timeline")
    func emptyEventsProducesEmptyTimeline() {
        let timeline = TimelineBuilder().build(from: [])
        #expect(timeline.events.isEmpty)
        #expect(timeline.phases.isEmpty)
    }

    @Test("Events are sorted by sequence number")
    func eventsSortedBySequenceNumber() {
        let events = [
            makeEnvelope(seq: 3, eventType: "third"),
            makeEnvelope(seq: 1, eventType: "first"),
            makeEnvelope(seq: 2, eventType: "second"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        #expect(timeline.events.map(\.eventType) == ["first", "second", "third"])
    }

    @Test("Duration is nil for empty timeline")
    func durationNilForEmpty() {
        let timeline = TimelineBuilder().build(from: [])
        #expect(timeline.duration == nil)
    }

    @Test("Duration is zero for single event")
    func durationNilForSingleEvent() {
        let timeline = TimelineBuilder().build(from: [makeEnvelope(seq: 1, eventType: "start")])
        #expect(timeline.duration == 0)
    }

    @Test("Duration computed from first and last event timestamps")
    func durationComputed() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let events = [
            makeEnvelope(seq: 1, eventType: "start", timestamp: t0),
            makeEnvelope(seq: 2, eventType: "end", timestamp: t1),
        ]
        let timeline = TimelineBuilder().build(from: events)
        #expect(timeline.duration == 10)
    }

    @Test("Planning phase events grouped correctly")
    func planningPhaseGrouped() {
        let events = [
            makeEnvelope(seq: 1, eventType: "commandIssued"),
            makeEnvelope(seq: 2, eventType: "planCommitted"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        #expect(timeline.phases.allSatisfy { $0.kind == .planning })
    }

    @Test("Execution phase events grouped correctly")
    func executionPhaseGrouped() {
        let events = [
            makeEnvelope(seq: 1, eventType: "actionStarted"),
            makeEnvelope(seq: 2, eventType: "actionCompleted"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        let hasExecution = timeline.phases.contains { $0.kind == .execution }
        #expect(hasExecution)
    }

    @Test("Mixed event types produce multiple phases")
    func mixedEventTypesProduceMultiplePhases() {
        let events = [
            makeEnvelope(seq: 1, eventType: "commandIssued"),
            makeEnvelope(seq: 2, eventType: "actionStarted"),
            makeEnvelope(seq: 3, eventType: "memoryCandidateCreated"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        #expect(timeline.phases.count >= 2)
    }

    @Test("TimelinePhaseKind maps commit event correctly")
    func commitPhaseKind() {
        let events = [
            makeEnvelope(seq: 1, eventType: "artifactProduced"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        #expect(timeline.phases.first?.kind == .commit)
    }

    @Test("TimelinePhaseKind maps learning event correctly")
    func learningPhaseKind() {
        let events = [
            makeEnvelope(seq: 1, eventType: "commandIssued"),
            makeEnvelope(seq: 2, eventType: "memoryPromoted"),
        ]
        let timeline = TimelineBuilder().build(from: events)
        let hasLearning = timeline.phases.contains { $0.kind == .learning }
        #expect(hasLearning)
    }
}
