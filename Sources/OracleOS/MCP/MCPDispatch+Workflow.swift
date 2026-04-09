import Foundation

// MCPDispatch+Workflow.swift — Workflow tool implementations.
//
// Covers: oracle_workflow_list, oracle_workflow_mine, oracle_workflow_execute

private struct WorkflowSummaryPayload: Encodable {
    let workflows: [WorkflowSummary]
    let count: Int
}

private struct WorkflowMinePayload: Encodable {
    let synthesized: Int
    let workflows: [WorkflowSummary]
}

private struct WorkflowExecutePayload: Encodable {
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

private struct WorkflowSummary: Encodable {
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

private struct WorkflowStepSummary: Encodable {
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
            let workflows = plans.map {
                WorkflowSummary(
                    id: $0.id,
                    goalPattern: $0.goalPattern,
                    successRate: $0.successRate,
                    stepCount: $0.steps.count,
                    parameterSlots: $0.parameterSlots,
                    promotionStatus: $0.promotionStatus.rawValue
                )
            }
            return typedResult(WorkflowSummaryPayload(workflows: workflows, count: workflows.count))

        case MCPToolName.workflowMine:
            guard let goalPattern = request.string("goal_pattern") else {
                return ToolResult(success: false, error: "goal_pattern is required for \(MCPToolName.workflowMine)")
            }
            let limit = request.int("limit") ?? 1000
            let events = container.traceStore.loadRecentEvents(limit: limit)
            let synthesized = WorkflowSynthesizer().synthesize(goalPattern: goalPattern, events: events)
            if synthesized.isEmpty {
                return typedResult(
                    WorkflowMinePayload(synthesized: 0, workflows: []),
                    suggestion: "No repeatable patterns found for '\(goalPattern)'. Run more successful traces to build workflow patterns."
                )
            }
            let index = WorkflowIndex()
            for plan in synthesized { index.add(plan) }
            let workflows = synthesized.map {
                WorkflowSummary(
                    id: $0.id,
                    goalPattern: $0.goalPattern,
                    successRate: $0.successRate,
                    stepCount: $0.steps.count,
                    parameterSlots: $0.parameterSlots,
                    promotionStatus: nil
                )
            }
            return typedResult(
                WorkflowMinePayload(synthesized: synthesized.count, workflows: workflows),
                suggestion: "Synthesized \(synthesized.count) workflow(s) and saved to index. Use oracle_workflow_list to see all."
            )

        case MCPToolName.workflowExecute:
            guard let workflowID = request.string("workflow_id") else {
                return ToolResult(success: false, error: "workflow_id is required for \(MCPToolName.workflowExecute)")
            }
            let index = WorkflowIndex()
            guard let plan = index.plan(id: workflowID) else {
                return ToolResult(
                    success: false,
                    error: "Workflow '\(workflowID)' not found.",
                    suggestion: "Use oracle_workflow_list to see available workflow IDs."
                )
            }
            let steps = plan.steps.enumerated().map { index, step in
                WorkflowStepSummary(
                    step: index + 1,
                    agentKind: step.agentKind.rawValue,
                    skill: step.actionContract.skillName,
                    domain: step.actionContract.domain,
                    notes: step.notes.isEmpty ? nil : step.notes,
                    query: step.semanticQuery?.text
                )
            }
            return typedResult(
                WorkflowExecutePayload(
                    workflowID: plan.id,
                    goalPattern: plan.goalPattern,
                    stepCount: plan.steps.count,
                    parameterSlots: plan.parameterSlots,
                    steps: steps
                ),
                suggestion: "Follow steps in order using the appropriate oracle tools. Substitute parameter_slots values as needed."
            )

        default:
            return ToolResult(success: false, error: "Unknown workflow tool: \(request.name)")
        }
    }
}
