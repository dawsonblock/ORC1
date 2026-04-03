import Foundation
import Testing
@testable import OracleControllerShared

struct ControllerSharedTests {
    @Test
    func actionRequestFlagsRiskyOperations() {
        let request = ActionRequest(kind: .click, query: "Send button")
        #expect(request.requiresConfirmation)

        let safeRequest = ActionRequest(kind: .focus, appName: "Finder")
        #expect(!safeRequest.requiresConfirmation)
    }

    @Test
    func hostRequestRoundTripsThroughJSON() throws {
        let request = ControllerHostRequest(
            command: .performAction,
            appName: "Google Chrome",
            action: ActionRequest(kind: .type, appName: "Google Chrome", query: "Search", text: "oracle"),
            monitoring: MonitoringConfiguration(enabled: true, appName: "Google Chrome", intervalMs: 1000)
        )

        let encoder = ControllerJSONCoding.makeEncoder()
        let decoder = ControllerJSONCoding.makeDecoder()

        let encoded = try encoder.encode(request)
        let decoded = try decoder.decode(ControllerHostRequest.self, from: encoded)

        #expect(decoded.command == .performAction)
        #expect(decoded.action?.text == "oracle")
        #expect(decoded.monitoring?.enabled == true)
    }

    @Test
    func traceEnvelopeRoundTrips() throws {
        let step = TraceStepViewModel(
            sessionID: "session-1",
            stepID: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            toolName: "oracle_focus",
            actionName: "focus",
            actionTarget: "Finder",
            actionText: nil,
            selectedElementID: nil,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            preObservationHash: "pre",
            postObservationHash: "post",
            postcondition: "appFrontmost:Finder",
            verified: true,
            success: true,
            failureClass: nil,
            elapsedMs: 42,
            screenshotPath: nil,
            artifactPaths: [],
            notes: nil
        )
        let event = ControllerHostEvent(kind: .traceStepAppended, traceStep: step)
        let envelope = ControllerHostEnvelope(event: event)

        let encoder = ControllerJSONCoding.makeEncoder()
        let decoder = ControllerJSONCoding.makeDecoder()

        let encoded = try encoder.encode(envelope)
        let decoded = try decoder.decode(ControllerHostEnvelope.self, from: encoded)

        #expect(decoded.kind == .event)
        #expect(decoded.event?.traceStep?.stepID == 1)
        #expect(decoded.event?.traceStep?.postObservationHash == "post")
    }

    @Test
    func recipeDocumentPreservesRawJSON() throws {
        let recipe = RecipeDocument(
            name: "gmail-send",
            description: "Send an email from Gmail.",
            app: "Google Chrome",
            params: [
                "recipient": RecipeParamDocument(id: "recipient", type: "string", description: "Email", required: true),
            ],
            steps: [
                RecipeStepDocument(id: 1, action: "focus"),
                RecipeStepDocument(id: 2, action: "click"),
            ],
            rawJSON: "{ \"name\": \"gmail-send\" }"
        )

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(RecipeDocument.self, from: data)

        #expect(decoded.name == "gmail-send")
        #expect(decoded.params?["recipient"]?.required == true)
        #expect(decoded.rawJSON == "{ \"name\": \"gmail-send\" }")
    }

    @Test
    func actionRunResultDistinguishesObservedWaitFromVerifiedExecution() {
        let observedWait = ActionRunResult(
            request: ActionRequest(kind: .wait, waitCondition: "windowTitleContains", waitValue: "Inbox"),
            success: true,
            verified: false,
            elapsedMs: 25,
            executedThroughExecutor: false
        )

        let verifiedClick = ActionRunResult(
            request: ActionRequest(kind: .click, query: "Send"),
            success: true,
            verified: true,
            elapsedMs: 42,
            executedThroughExecutor: true
        )

        #expect(observedWait.disposition == .observed)
        #expect(observedWait.statusLabel == "Observed")
        #expect(observedWait.executionPathSummary == "Observed wait condition in the host bridge")

        #expect(verifiedClick.disposition == .verifiedExecution)
        #expect(verifiedClick.statusLabel == "Verified")
        #expect(verifiedClick.executionPathSummary == "Executed through the verified runtime path")
    }

    @Test
    func actionRunResultPrefersApprovalPendingOverFailureLabel() {
        let pending = ActionRunResult(
            request: ActionRequest(kind: .click, query: "Delete"),
            success: false,
            verified: false,
            failureClass: "approval_pending",
            elapsedMs: 0,
            approvalRequestID: "approval-1",
            approvalStatus: "pending",
            executedThroughExecutor: false
        )

        #expect(pending.disposition == .awaitingApproval)
        #expect(pending.statusLabel == "Awaiting Approval")
        #expect(pending.summaryText == "Action awaiting approval before runtime execution.")
    }
}
