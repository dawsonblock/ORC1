import Foundation

// MCPDispatch+Workflow.swift — Workflow tool implementations.
//
// Covers: oracle_workflow_list, oracle_workflow_mine, oracle_workflow_execute

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
            let serialized: [[String: Any]] = plans.map { p in [
                "id": p.id,
                "goal_pattern": p.goalPattern,
                "success_rate": p.successRate,
                "step_count": p.steps.count,
                "parameter_slots": p.parameterSlots,
                "promotion_status": p.promotionStatus.rawValue,
            ] }
            return ToolResult(success: true, data: ["workflows": serialized, "count": serialized.count])

        case MCPToolName.workflowMine:
            guard let goalPattern = request.string("goal_pattern") else {
                return ToolResult(success: false, error: "goal_pattern is required for \(MCPToolName.workflowMine)")
            }
            let limit = request.int("limit") ?? 1000
            let events = container.traceStore.loadRecentEvents(limit: limit)
            let synthesized = WorkflowSynthesizer().synthesize(goalPattern: goalPattern, events: events)
            if synthesized.isEmpty {
                return ToolResult(
                    success: true,
                    data: ["synthesized": 0, "workflows": [[String: Any]]()],
                    suggestion: "No repeatable patterns found for '\(goalPattern)'. Run more successful traces to build workflow patterns."
                )
            }
            let index = WorkflowIndex()
            for plan in synthesized { index.add(plan) }
            let serialized: [[String: Any]] = synthesized.map { p in [
                "id": p.id,
                "goal_pattern": p.goalPattern,
                "success_rate": p.successRate,
                "step_count": p.steps.count,
                "parameter_slots": p.parameterSlots,
            ] }
            return ToolResult(
                success: true,
                data: ["synthesized": synthesized.count, "workflows": serialized],
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
            let steps: [[String: Any]] = plan.steps.enumerated().map { idx, s in
                var d: [String: Any] = [
                    "step": idx + 1,
                    "agent_kind": s.agentKind.rawValue,
                    "skill": s.actionContract.skillName,
                    "domain": s.actionContract.domain,
                ]
                if !s.notes.isEmpty { d["notes"] = s.notes }
                if let q = s.semanticQuery?.text { d["query"] = q }
                return d
            }
            return ToolResult(
                success: true,
                data: [
                    "workflow_id": plan.id,
                    "goal_pattern": plan.goalPattern,
                    "step_count": plan.steps.count,
                    "parameter_slots": plan.parameterSlots,
                    "steps": steps,
                ],
                suggestion: "Follow steps in order using the appropriate oracle tools. Substitute parameter_slots values as needed."
            )

        default:
            return ToolResult(success: false, error: "Unknown workflow tool: \(request.name)")
        }
    }
}
