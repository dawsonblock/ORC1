import Foundation
import Testing

@testable import OracleOS

@Suite("Workflow Executor")
struct WorkflowExecutorTests {

    @Test("Exact planning state match beats generic fallback")
    func exactPlanningStateMatchBeatsGenericFallback() {
        let executor = WorkflowExecutor()
        let plan = WorkflowPlan(
            agentKind: .code,
            goalPattern: "read package manifest",
            steps: [
                WorkflowStep(
                    id: "generic-step",
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "workflow|code|generic-read",
                        agentKind: .code,
                        skillName: "readFile",
                        targetRole: nil,
                        targetLabel: "README.md",
                        locatorStrategy: "workflow",
                        workspaceRelativePath: "README.md",
                        commandCategory: CodeCommandCategory.openFile.rawValue,
                        plannerFamily: PlannerFamily.code.rawValue
                    )
                ),
                WorkflowStep(
                    id: "exact-step",
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "workflow|code|exact-read",
                        agentKind: .code,
                        skillName: "readFile",
                        targetRole: nil,
                        targetLabel: "Package.swift",
                        locatorStrategy: "workflow",
                        workspaceRelativePath: "Package.swift",
                        commandCategory: CodeCommandCategory.openFile.rawValue,
                        plannerFamily: PlannerFamily.code.rawValue
                    ),
                    fromPlanningStateID: "workspace|dirty"
                ),
            ],
            successRate: 1
        )

        let match = executor.match(plan: plan, planningStateID: "workspace|dirty")

        #expect(match?.stepIndex == 1)
    }

    @Test("Generic fallback is used when no exact planning state exists")
    func genericFallbackUsedWhenNoExactPlanningStateExists() {
        let executor = WorkflowExecutor()
        let plan = WorkflowPlan(
            agentKind: .code,
            goalPattern: "read package manifest",
            steps: [
                WorkflowStep(
                    id: "generic-step",
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "workflow|code|generic-read",
                        agentKind: .code,
                        skillName: "readFile",
                        targetRole: nil,
                        targetLabel: "README.md",
                        locatorStrategy: "workflow",
                        workspaceRelativePath: "README.md",
                        commandCategory: CodeCommandCategory.openFile.rawValue,
                        plannerFamily: PlannerFamily.code.rawValue
                    )
                ),
                WorkflowStep(
                    id: "exact-step",
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "workflow|code|exact-read",
                        agentKind: .code,
                        skillName: "readFile",
                        targetRole: nil,
                        targetLabel: "Package.swift",
                        locatorStrategy: "workflow",
                        workspaceRelativePath: "Package.swift",
                        commandCategory: CodeCommandCategory.openFile.rawValue,
                        plannerFamily: PlannerFamily.code.rawValue
                    ),
                    fromPlanningStateID: "workspace|dirty"
                ),
            ],
            successRate: 1
        )

        let match = executor.match(plan: plan, planningStateID: "workspace|clean")

        #expect(match?.stepIndex == 0)
    }
}
