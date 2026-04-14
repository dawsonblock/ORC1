import Foundation

public struct WorkflowExecutor: Sendable {
    public init() {}

    public func match(
        plan: WorkflowPlan,
        planningStateID: String?,
        projectMemoryRefs: [ProjectMemoryRef] = []
    ) -> WorkflowMatch? {
        guard let stepIndex = matchingStepIndex(plan: plan, planningStateID: planningStateID) else {
            return nil
        }

        return WorkflowMatch(
            plan: plan,
            stepIndex: stepIndex,
            score: 1,
            projectMemoryRefs: projectMemoryRefs
        )
    }

    public func nextDecision(
        match: WorkflowMatch,
        plannerFamily: PlannerFamily,
        sourceNotes: [String] = []
    ) -> PlannerDecision {
        let step = match.plan.steps[match.stepIndex]
        return PlannerDecision(
            agentKind: step.agentKind,
            skillName: step.actionContract.skillName,
            plannerFamily: plannerFamily,
            stepPhase: step.stepPhase,
            actionContract: step.actionContract,
            source: .workflow,
            workflowID: match.plan.id,
            workflowStepID: step.id,
            fallbackReason: nil,
            semanticQuery: step.semanticQuery,
            projectMemoryRefs: match.projectMemoryRefs,
            notes: ["workflow \(match.plan.goalPattern)"] + sourceNotes + step.notes
        )
    }

    private func matchingStepIndex(plan: WorkflowPlan, planningStateID: String?) -> Int? {
        if let planningStateID,
            let index = plan.steps.firstIndex(where: { $0.fromPlanningStateID == planningStateID })
        {
            return index
        }

        return plan.steps.firstIndex(where: { $0.fromPlanningStateID == nil })
    }
}
