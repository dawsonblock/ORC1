import Foundation

// MCPDispatch+Workflow.swift — Workflow tool implementations.
//
// Workflow indexing here remains a bounded service-persistence surface.
// Persisted workflow plans are support material and do not redefine the main
// execution spine or commit authority.
//
// Covers: oracle_workflow_list, oracle_workflow_mine, oracle_workflow_execute

private struct WorkflowListItem: Encodable {
    let id: String
    let goalPattern: String
    let successRate: Double
    let stepCount: Int
    let parameterSlots: [String]
    let promotionStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case goalPattern = "goal_pattern"
        case successRate = "success_rate"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case promotionStatus = "promotion_status"
    }
}

private struct WorkflowListPayload: Encodable {
    let workflows: [WorkflowListItem]
    let count: Int
}

private struct WorkflowMineItem: Encodable {
    let id: String
    let goalPattern: String
    let successRate: Double
    let stepCount: Int
    let parameterSlots: [String]
    let promotionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case goalPattern = "goal_pattern"
        case successRate = "success_rate"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case promotionStatus = "promotion_status"
    }
}

private struct WorkflowMinePayload: Encodable {
    let synthesized: Int
    let workflows: [WorkflowMineItem]
}

struct WorkflowStepSummary: Encodable {
    let step: Int
    let agentKind: String
    let skill: String
    let domain: String
    let notes: String?
    let query: String?

    enum CodingKeys: String, CodingKey {
        case step
        case agentKind = "agent_kind"
        case skill
        case domain
        case notes
        case query
    }
}

struct WorkflowExecutePayload: Encodable {
    let workflowID: String
    let goalPattern: String
    let stepCount: Int
    let parameterSlots: [String]
    let steps: [WorkflowStepSummary]

    enum CodingKeys: String, CodingKey {
        case workflowID = "workflow_id"
        case goalPattern = "goal_pattern"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case steps
    }
}

extension MCPDispatch {
    @MainActor
    static func dispatchWorkflow(
        _ request: MCPToolRequest,
        container: RuntimeContainer
    ) -> ToolResult {
        switch request.name {

        case MCPToolName.workflowList:
            let index = WorkflowIndex()
            let plans = index.allPlans()
            let payload = WorkflowListPayload(
                workflows: plans.map { plan in
                    WorkflowListItem(
                        id: plan.id,
                        goalPattern: plan.goalPattern,
                        successRate: plan.successRate,
                        stepCount: plan.steps.count,
                        parameterSlots: plan.parameterSlots,
                        promotionStatus: plan.promotionStatus.rawValue
                    )
                },
                count: plans.count
            )
            return typedResult(payload)

        case MCPToolName.workflowMine:
            guard let goalPattern = request.string("goal_pattern") else {
                return ToolResult(
                    success: false,
                    error: "goal_pattern is required for \(MCPToolName.workflowMine)")
            }
            let limit = request.int("limit") ?? 1000
            let events = container.traceStore.loadRecentEvents(limit: limit)
            let synthesized = WorkflowSynthesizer().synthesize(
                goalPattern: goalPattern, events: events)
            if synthesized.isEmpty {
                return typedResult(
                    WorkflowMinePayload(synthesized: 0, workflows: []),
                    suggestion:
                        "No repeatable patterns found for '\(goalPattern)'. Run more successful traces to build workflow patterns."
                )
            }

            let index = WorkflowIndex()
            for plan in synthesized {
                index.add(plan)
            }
            let payload = WorkflowMinePayload(
                synthesized: synthesized.count,
                workflows: synthesized.map { plan in
                    WorkflowMineItem(
                        id: plan.id,
                        goalPattern: plan.goalPattern,
                        successRate: plan.successRate,
                        stepCount: plan.steps.count,
                        parameterSlots: plan.parameterSlots,
                        promotionStatus: nil
                    )
                }
            )
            return typedResult(
                payload,
                suggestion:
                    "Synthesized \(synthesized.count) workflow(s) and saved to index. Use oracle_workflow_list to see all."
            )

        case MCPToolName.workflowExecute:
            guard let workflowID = request.string("workflow_id") else {
                return ToolResult(
                    success: false,
                    error: "workflow_id is required for \(MCPToolName.workflowExecute)")
            }
            let index = WorkflowIndex()
            guard let plan = index.plan(id: workflowID) else {
                return ToolResult(
                    success: false,
                    error: "Workflow '\(workflowID)' not found.",
                    suggestion: "Use oracle_workflow_list to see available workflow IDs."
                )
            }
            let payload = WorkflowExecutePayload(
                workflowID: plan.id,
                goalPattern: plan.goalPattern,
                stepCount: plan.steps.count,
                parameterSlots: plan.parameterSlots,
                steps: plan.steps.enumerated().map { index, step in
                    WorkflowStepSummary(
                        step: index + 1,
                        agentKind: step.agentKind.rawValue,
                        skill: step.actionContract.skillName,
                        domain: step.actionContract.domain,
                        notes: step.notes.isEmpty ? nil : step.notes.joined(separator: "\n"),
                        query: step.semanticQuery?.text
                    )
                }
            )
            return typedResult(
                payload,
                suggestion:
                    "Follow steps in order using the appropriate oracle tools. Substitute parameter_slots values as needed."
            )

        default:
            return ToolResult(success: false, error: "Unknown workflow tool: \(request.name)")
        }
    }
}
