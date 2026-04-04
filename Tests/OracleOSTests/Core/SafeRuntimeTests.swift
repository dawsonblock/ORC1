import Foundation
import Testing
@testable import OracleOS

@MainActor
@Suite("Safe Runtime")
struct SafeRuntimeTests {

    @Test("Policy allows low-risk focus in confirm-risky mode")
    func policyAllowsLowRiskFocus() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let decision = engine.evaluate(
            intent: .focus(app: "Finder"),
            context: PolicyEvaluationContext(surface: .mcp, toolName: "oracle_focus", appName: "Finder")
        )

        #expect(decision.allowed)
        #expect(decision.requiresApproval == false)
        #expect(decision.blockedByPolicy == false)
    }

    @Test("Policy requires approval for send actions in browser contexts")
    func policyRequiresApprovalForSend() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let intent = ActionIntent.click(app: "Google Chrome", query: "Send")
        let decision = engine.evaluate(
            intent: intent,
            context: PolicyEvaluationContext(surface: .mcp, toolName: "oracle_click", appName: "Google Chrome")
        )

        #expect(decision.allowed == false)
        #expect(decision.requiresApproval)
        #expect(decision.protectedOperation == .send)
        #expect(decision.blockedByPolicy == false)
    }

    @Test("Policy blocks terminal interaction by default")
    func policyBlocksTerminalControl() {
        let engine = PolicyEngine(mode: .confirmRisky)
        let decision = engine.evaluate(
            intent: .press(app: "Terminal", key: "return"),
            context: PolicyEvaluationContext(surface: .cli, toolName: "oracle_press", appName: "Terminal")
        )

        #expect(decision.allowed == false)
        #expect(decision.blockedByPolicy)
        #expect(decision.protectedOperation == .terminalControl)
    }

    @Test("Approval receipts are single use")
    func approvalReceiptsSingleUse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ApprovalStore(rootDirectory: root)
        let request = ApprovalRequest(
            surface: .controller,
            toolName: "oracle_click",
            appName: "Google Chrome",
            displayTitle: "Click Send",
            reason: "Action requires approval",
            riskLevel: .risky,
            protectedOperation: .send,
            actionFingerprint: "fingerprint-send",
            appProtectionProfile: .confirmRisky
        )

        _ = try store.createRequest(request)
        _ = try store.approve(requestID: request.id)

        let firstReceipt = store.consumeApprovedReceipt(requestID: request.id, actionFingerprint: "fingerprint-send")
        let secondReceipt = store.consumeApprovedReceipt(requestID: request.id, actionFingerprint: "fingerprint-send")

        #expect(firstReceipt != nil)
        #expect(firstReceipt?.consumed == true)
        #expect(secondReceipt == nil)
    }

    @Test("Approval receipts are action-fingerprint bound")
    func approvalReceiptsRejectMismatchedFingerprint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ApprovalStore(rootDirectory: root)

        let approvedCommand = Command(
            type: .ui,
            payload: .ui(UIAction(name: "click", app: "Google Chrome", query: "Send")),
            metadata: CommandMetadata(intentID: UUID(), source: "test")
        )
        let differentCommand = Command(
            type: .ui,
            payload: .ui(UIAction(name: "click", app: "Google Chrome", query: "Delete")),
            metadata: CommandMetadata(intentID: UUID(), source: "test")
        )

        let request = ApprovalRequest(
            surface: .controller,
            toolName: "oracle_click",
            appName: "Google Chrome",
            displayTitle: "Click Send",
            reason: "Action requires approval",
            riskLevel: .risky,
            protectedOperation: .send,
            actionFingerprint: PolicyRules.commandFingerprint(approvedCommand),
            appProtectionProfile: .confirmRisky
        )

        _ = try store.createRequest(request)
        _ = try store.approve(requestID: request.id)

        let mismatched = store.consumeApprovedReceipt(
            requestID: request.id,
            actionFingerprint: PolicyRules.commandFingerprint(differentCommand)
        )
        let matched = store.consumeApprovedReceipt(
            requestID: request.id,
            actionFingerprint: PolicyRules.commandFingerprint(approvedCommand)
        )

        #expect(mismatched == nil)
        #expect(matched != nil)
        #expect(matched?.consumed == true)
    }
}
