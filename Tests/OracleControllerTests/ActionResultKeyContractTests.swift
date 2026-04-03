import XCTest
@testable import OracleOS

// MARK: - ActionResultKeyContractTests
//
// PURPOSE: Verify that ActionResult.toDict() serialises approval/policy fields using
// the exact key strings that ControllerRuntimeBridge+Mapping.mapActionResult consumes.
//
// WHY THIS MATTERS: mapActionResult lives in OracleControllerHost (an executable target)
// and cannot be imported by test targets. These tests validate the producer-side
// dictionary contract so that any key-string drift is caught at the OracleOS boundary
// before it silently breaks the bridge consumer.

final class ActionResultKeyContractTests: XCTestCase {

    // MARK: ActionResultKey string values (must match what mapActionResult probes)

    func testApprovalRequestIDKeyString() {
        XCTAssertEqual(ActionResultKey.approvalRequestID, "approval_request_id")
    }

    func testApprovalStatusKeyString() {
        XCTAssertEqual(ActionResultKey.approvalStatus, "approval_status")
    }

    func testBlockedByPolicyKeyString() {
        XCTAssertEqual(ActionResultKey.blockedByPolicy, "blocked_by_policy")
    }

    // MARK: CodeExecutionResultKey string values

    func testCommandCategoryKeyString() {
        XCTAssertEqual(CodeExecutionResultKey.commandCategory, "command_category")
    }

    func testCommandSummaryKeyString() {
        XCTAssertEqual(CodeExecutionResultKey.commandSummary, "summary")
    }

    func testWorkspaceRelativePathKeyString() {
        XCTAssertEqual(CodeExecutionResultKey.workspaceRelativePath, "workspace_relative_path")
    }

    // MARK: ActionResult.toDict() approval-pending path

    func testActionResultToDictPreservesApprovalPendingFields() {
        let result = ActionResult(
            success: false,
            approvalRequestID: "req-abc-123",
            approvalStatus: "pending"
        )
        let dict = result.toDict()

        XCTAssertEqual(dict[ActionResultKey.approvalRequestID] as? String, "req-abc-123")
        XCTAssertEqual(dict[ActionResultKey.approvalStatus] as? String, "pending")
        XCTAssertFalse(dict[ActionResultKey.blockedByPolicy] as? Bool ?? true)
    }

    // MARK: ActionResult.toDict() blocked-by-policy path

    func testActionResultToDictPreservesBlockedByPolicyTrue() {
        let result = ActionResult(
            success: false,
            blockedByPolicy: true
        )
        let dict = result.toDict()

        XCTAssertTrue(dict[ActionResultKey.blockedByPolicy] as? Bool ?? false)
        XCTAssertNil(dict[ActionResultKey.approvalRequestID])
        XCTAssertNil(dict[ActionResultKey.approvalStatus])
    }

    // MARK: ActionResult.toDict() normal success path

    func testActionResultToDictNormalSuccessPath() {
        let result = ActionResult(
            success: true,
            verified: true,
            executedThroughExecutor: true
        )
        let dict = result.toDict()

        XCTAssertTrue(dict[ActionResultKey.success] as? Bool ?? false)
        XCTAssertTrue(dict[ActionResultKey.verified] as? Bool ?? false)
        XCTAssertFalse(dict[ActionResultKey.blockedByPolicy] as? Bool ?? true)
        XCTAssertTrue(dict[ActionResultKey.executedThroughExecutor] as? Bool ?? false)
        XCTAssertNil(dict[ActionResultKey.approvalRequestID])
    }
}
