import Foundation
import Testing
@testable import OracleOS

@Suite("RuntimeExecutionDriver Boundary")
@MainActor
struct RuntimeExecutionDriverBoundaryTests {

    @Test("RuntimeExecutionDriver emits structured action_result payload")
    func runtimeExecutionDriverEmitsStructuredActionResultPayload() {
        let response = IntentResponse(
            intentID: UUID(),
            outcome: .success,
            summary: "Intent completed",
            cycleID: UUID(),
            snapshotID: UUID()
        )
        let driver = RuntimeExecutionDriver(
            intentAPI: StubIntentAPI(response: response),
            surface: .controller
        )

        let result = driver.execute(
            intent: ActionIntent.click(app: nil, query: "Save"),
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        let actionResult = result.data?["action_result"] as? [String: Any]
        #expect(result.success == true)
        #expect(result.data?["method"] as? String == "intent-api")
        #expect(actionResult?["executed_through_executor"] as? Bool == true)
        #expect(result.actionResult?.executedThroughExecutor == true)
        #expect(result.traceResult?.cycleID == response.cycleID.uuidString)
    }

    @Test("Planning-failure responses are marked as non-executed")
    func planningFailureResponsesAreMarkedNonExecuted() {
        let response = IntentResponse(
            intentID: UUID(),
            outcome: .failed,
            summary: "Planning failed: no viable command",
            cycleID: UUID(),
            snapshotID: nil
        )
        let driver = RuntimeExecutionDriver(
            intentAPI: StubIntentAPI(response: response),
            surface: .mcp
        )

        let result = driver.execute(
            intent: ActionIntent.click(app: nil, query: "Save"),
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        let actionResult = result.data?["action_result"] as? [String: Any]
        #expect(result.success == false)
        #expect(actionResult?["executed_through_executor"] as? Bool == false)
    }

    @Test("Partial-success responses stay successful but not verified")
    func partialSuccessResponsesStaySuccessfulButNotVerified() {
        let response = IntentResponse(
            intentID: UUID(),
            outcome: .partialSuccess,
            summary: "Intent completed with partial verification",
            cycleID: UUID(),
            snapshotID: UUID()
        )
        let driver = RuntimeExecutionDriver(
            intentAPI: StubIntentAPI(response: response),
            surface: .controller
        )

        let result = driver.execute(
            intent: ActionIntent.click(app: nil, query: "Save"),
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        let actionResult = result.data?["action_result"] as? [String: Any]
        #expect(result.success == true)
        #expect(actionResult?["success"] as? Bool == true)
        #expect(actionResult?["verified"] as? Bool == false)
        #expect(actionResult?["failure_class"] as? String == "partial_success")
        #expect(actionResult?["executed_through_executor"] as? Bool == true)
    }

    @Test("Approval-pending responses preserve approval metadata and stay non-executed")
    func approvalPendingResponsesPreserveApprovalMetadata() {
        let response = IntentResponse(
            intentID: UUID(),
            outcome: .failed,
            summary: "Intent completed: delete draft - approvalPending",
            cycleID: UUID(),
            approvalRequestID: "approval-1",
            approvalStatus: "pending"
        )
        let driver = RuntimeExecutionDriver(
            intentAPI: StubIntentAPI(response: response),
            surface: .controller
        )

        let result = driver.execute(
            intent: ActionIntent.click(app: nil, query: "Delete"),
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        let actionResult = result.data?["action_result"] as? [String: Any]
        #expect(result.success == false)
        #expect(actionResult?["approval_request_id"] as? String == "approval-1")
        #expect(actionResult?["approval_status"] as? String == "pending")
        #expect(actionResult?["executed_through_executor"] as? Bool == false)
        #expect(result.actionResult?.approvalRequestID == "approval-1")
        #expect(result.actionResult?.approvalStatus == "pending")
    }

    @Test("Planner normalizes empty action-intent app to nil")
    func plannerNormalizesEmptyActionIntentAppToNil() async throws {
        let planner = MainPlanner()
        let actionIntent = ActionIntent.click(app: nil, query: "Save")
        let encoded = try JSONEncoder().encode(actionIntent).base64EncodedString()
        let intent = Intent(
            domain: .ui,
            objective: "click save",
            metadata: ["action_intent_base64": encoded]
        )

        let command = try await planner.plan(intent: intent, context: PlannerContext(state: WorldStateModel()))
        guard case .ui(let uiAction) = command.payload else {
            Issue.record("Expected UI command payload")
            return
        }
        #expect(uiAction.app == nil)
    }

    @Test("Planner normalizes legacy 'unknown' app to nil")
    func plannerNormalizesUnknownAppToNil() async throws {
        let planner = MainPlanner()
        let legacyIntent = ActionIntent(
            app: "unknown",
            action: "click",
            query: "Save"
        )
        let encoded = try JSONEncoder().encode(legacyIntent).base64EncodedString()
        let intent = Intent(
            domain: .ui,
            objective: "click save",
            metadata: ["action_intent_base64": encoded]
        )

        let command = try await planner.plan(intent: intent, context: PlannerContext(state: WorldStateModel()))
        guard case .ui(let uiAction) = command.payload else {
            Issue.record("Expected UI command payload")
            return
        }
        #expect(uiAction.app == nil)
    }

    private func testPlannerDecision() -> PlannerDecision {
        PlannerDecision(
            actionContract: ActionContract(
                id: "test|click|save",
                skillName: "click",
                targetRole: nil,
                targetLabel: "Save",
                locatorStrategy: "query"
            ),
            source: .strategy
        )
    }
}

private actor StubIntentAPI: IntentAPI {
    private let response: IntentResponse

    init(response: IntentResponse) {
        self.response = response
    }

    func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        _ = intent
        return response
    }

    func queryState() async throws -> RuntimeSnapshot {
        RuntimeSnapshot()
    }
}
