import XCTest

@testable import OracleOS

@MainActor
final class MCPTypedBoundarySerializationTests: XCTestCase {
    func testOuterSeamRejectsMissingName() async {
        let response = await MCPDispatch.handle(["arguments": ["query": "Save"]])
        let content = response["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""

        XCTAssertEqual(response["isError"] as? Bool, true)
        XCTAssertTrue(text.contains("missing required field"))
    }

    func testWorkflowPayloadSerializesStableKeys() {
        let payload = WorkflowExecutePayload(
            workflowID: "wf-1",
            goalPattern: "archive mail",
            stepCount: 2,
            parameterSlots: ["account"],
            steps: [
                WorkflowStepSummary(
                    step: 1,
                    agentKind: "ui",
                    skill: "click",
                    domain: "ui",
                    notes: "focus mailbox",
                    query: "Archive"
                )
            ]
        )

        let dict = MCPDispatch.legacyDict(for: payload)
        XCTAssertEqual(dict?["workflow_id"] as? String, "wf-1")
        XCTAssertEqual(dict?["goal_pattern"] as? String, "archive mail")
        XCTAssertEqual(dict?["step_count"] as? Int, 2)
    }

    func testMemoryPayloadSerializesStableKeys() {
        let payload = MemoryQueryPayload(
            records: [
                MemoryRecordSummary(
                    id: "mem-1",
                    kind: "risk",
                    title: "Sandbox boundary",
                    summary: "Keep experiments isolated",
                    knowledgeClass: "reusable",
                    affectedModules: ["Experiments"],
                    body: "Details",
                    evidenceRefs: ["Tests/OracleOSTests/Experiments"]
                )
            ],
            count: 1
        )

        let dict = MCPDispatch.legacyDict(for: payload)
        let records = dict?["records"] as? [[String: Any]]
        XCTAssertEqual(records?.first?["knowledge_class"] as? String, "reusable")
        XCTAssertEqual(records?.first?["affected_modules"] as? [String], ["Experiments"])
    }

    func testRecipePayloadSerializesStableKeys() {
        let payload = RecipeSummaryPayload(
            recipes: [
                RecipeSummary(
                    name: "gmail_archive", description: "Archive mail", parameters: ["label"])
            ],
            count: 1
        )

        let dict = MCPDispatch.legacyDict(for: payload)
        let recipes = dict?["recipes"] as? [[String: Any]]
        XCTAssertEqual(recipes?.first?["name"] as? String, "gmail_archive")
        XCTAssertEqual(recipes?.first?["parameters"] as? [String], ["label"])
    }

    func testArchitecturePayloadSerializesStableKeys() {
        let payload = ArchitectureReviewPayload(
            triggered: true,
            riskScore: 0.7,
            affectedModules: ["MCP"],
            findings: [
                ArchitectureFindingPayload(
                    title: "Bypass risk",
                    summary: "Avoid legacy probing",
                    severity: "warning",
                    riskScore: 0.7,
                    affectedModules: ["MCP"],
                    evidence: ["Sources/OracleOS/MCP/MCPDispatch.swift"]
                )
            ],
            refactorProposal: RefactorProposalPayload(
                id: "proposal-1",
                title: "Type payload export",
                summary: "Centralize encoding",
                steps: ["use Encodable"],
                riskScore: 0.2
            )
        )

        let dict = MCPDispatch.legacyDict(for: payload)
        XCTAssertEqual(dict?["risk_score"] as? Double, 0.7)
        XCTAssertNotNil(dict?["refactor_proposal"] as? [String: Any])
    }
}
