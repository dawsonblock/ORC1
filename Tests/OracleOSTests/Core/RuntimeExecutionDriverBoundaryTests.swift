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

    @Test("RuntimeExecutionDriver exports envelope-backed compatibility data")
    func runtimeExecutionDriverExportsEnvelopeBackedCompatibilityData() {
        let snapshotID = UUID()
        let response = IntentResponse(
            intentID: UUID(),
            outcome: .success,
            summary: "Intent completed",
            cycleID: UUID(),
            snapshotID: snapshotID
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

        let trace = result.data?[ActionResultKey.trace] as? [String: Any]

        #expect(result.data?["summary"] as? String == response.summary)
        #expect(result.data?["snapshot_id"] as? String == snapshotID.uuidString)
        #expect(result.data?["cycleID"] == nil)
        #expect(trace?[TraceResultKey.cycleID] as? String == response.cycleID.uuidString)
        #expect(trace?[TraceResultKey.intentID] as? String == response.intentID.uuidString)
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

    @Test("Code action intents populate codeExecutionResult natively")
    func codeActionIntentsPopulateCodeExecutionResultNatively() {
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
        let intent = ActionIntent.code(
            command: CommandSpec(
                category: .build,
                executable: "swift",
                arguments: ["build"],
                workspaceRoot: "/tmp/workspace",
                workspaceRelativePath: "Package.swift",
                summary: "swift build"
            )
        )

        let result = driver.execute(
            intent: intent,
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        let codeExecutionData = result.data?[ActionResultKey.codeExecution] as? [String: Any]

        #expect(result.codeExecutionResult?.commandCategory == CodeCommandCategory.build.rawValue)
        #expect(result.codeExecutionResult?.commandSummary == "swift build")
        #expect(result.codeExecutionResult?.workspaceRelativePath == "Package.swift")
        #expect(
            codeExecutionData?[CodeExecutionResultKey.commandCategory] as? String
                == CodeCommandCategory.build.rawValue)
        #expect(
            codeExecutionData?[CodeExecutionResultKey.commandSummary] as? String == "swift build")
        #expect(
            codeExecutionData?[CodeExecutionResultKey.workspaceRelativePath] as? String
                == "Package.swift")
    }

    @Test("Code action submission failures keep native codeExecutionResult")
    func codeActionSubmissionFailuresKeepNativeCodeExecutionResult() {
        let driver = RuntimeExecutionDriver(
            intentAPI: ThrowingIntentAPI(),
            surface: .mcp
        )
        let intent = ActionIntent.code(
            command: CommandSpec(
                category: .test,
                executable: "swift",
                arguments: ["test"],
                workspaceRoot: "/tmp/workspace",
                workspaceRelativePath: "Tests/OracleOSTests",
                summary: "swift test"
            )
        )

        let result = driver.execute(
            intent: intent,
            plannerDecision: testPlannerDecision(),
            selectedCandidate: nil
        )

        #expect(result.success == false)
        #expect(result.codeExecutionResult?.commandCategory == CodeCommandCategory.test.rawValue)
        #expect(result.codeExecutionResult?.commandSummary == "swift test")
        #expect(result.codeExecutionResult?.workspaceRelativePath == "Tests/OracleOSTests")
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

        let command = try await planner.plan(
            intent: intent, context: PlannerContext(state: WorldStateModel()))
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

        let command = try await planner.plan(
            intent: intent, context: PlannerContext(state: WorldStateModel()))
        guard case .ui(let uiAction) = command.payload else {
            Issue.record("Expected UI command payload")
            return
        }
        #expect(uiAction.app == nil)
    }

    @Test("Planner preserves raw search query from ActionIntent code commands")
    func plannerPreservesRawSearchQueryFromActionIntentCodeCommands() async throws {
        let planner = MainPlanner()
        let actionIntent = ActionIntent.code(
            name: "searchRepository",
            command: CommandSpec(
                category: .searchCode,
                executable: "/usr/bin/env",
                arguments: ["UniqueWorkflowNeedle"],
                workspaceRoot: "/tmp/workspace",
                summary: "search code for UniqueWorkflowNeedle"
            )
        )
        let encoded = try JSONEncoder().encode(actionIntent).base64EncodedString()
        let intent = Intent(
            domain: .code,
            objective: "search UniqueWorkflowNeedle",
            metadata: ["action_intent_base64": encoded]
        )

        let command = try await planner.plan(
            intent: intent,
            context: PlannerContext(state: WorldStateModel())
        )
        guard case .code(let action) = command.payload else {
            Issue.record("Expected code command payload")
            return
        }

        #expect(action.name == "searchRepository")
        #expect(action.query == "UniqueWorkflowNeedle")
        #expect(action.workspacePath == "/tmp/workspace")
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

private actor ThrowingIntentAPI: IntentAPI {
    func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        _ = intent
        throw NSError(
            domain: "RuntimeExecutionDriverBoundaryTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "submit failed"])
    }

    func queryState() async throws -> RuntimeSnapshot {
        RuntimeSnapshot()
    }
}
