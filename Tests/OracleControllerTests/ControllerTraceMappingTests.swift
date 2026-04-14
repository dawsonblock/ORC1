import Foundation
import Testing

@testable import OracleControllerHost
@testable import OracleOS

struct ControllerTraceMappingTests {
    @Test("Projection prefers persisted experiment summary metadata")
    func projectionPrefersPersistedExperimentSummaryMetadata() {
        let event = makeEvent(experimentID: "exp-1")
        let summary = DiagnosticsExperimentSummary(
            id: "exp-1",
            candidateCount: 1,
            selectedCandidateID: "candidate-1",
            winningSandboxPath: "/tmp/oracle/workspace/.oracle/experiments/exp-1/candidate-1",
            executionContext: "persisted-summary",
            committedToWorkspace: false,
            succeededCandidateCount: 1,
            candidates: []
        )

        let projection = ExperimentTraceProjection.resolve(
            event: event,
            experimentSummary: summary
        )

        #expect(projection.executionContext == "persisted-summary")
        #expect(projection.committedToWorkspace == false)
    }

    @Test("Projection keeps sandbox-only fallback for trace-only experiment events")
    func projectionKeepsSandboxOnlyFallbackForTraceOnlyExperimentEvents() {
        let projection = ExperimentTraceProjection.resolve(
            event: makeEvent(experimentID: "exp-1"),
            experimentSummary: nil
        )

        #expect(projection.executionContext == ExperimentExecutionContext.sandbox.rawValue)
        #expect(projection.committedToWorkspace == false)
    }

    @Test("Projection leaves non-experiment trace events unannotated")
    func projectionLeavesNonExperimentTraceEventsUnannotated() {
        let projection = ExperimentTraceProjection.resolve(
            event: makeEvent(experimentID: nil),
            experimentSummary: nil
        )

        #expect(projection.executionContext == nil)
        #expect(projection.committedToWorkspace == nil)
    }

    private func makeEvent(experimentID: String?) -> TraceEvent {
        TraceEvent(
            sessionID: "session",
            taskID: nil,
            stepID: 1,
            toolName: "oracle_experiment_search",
            actionName: "oracle_experiment_search",
            verified: true,
            success: true,
            experimentID: experimentID,
            elapsedMs: 1
        )
    }
}
