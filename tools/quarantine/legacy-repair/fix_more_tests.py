with open("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "a") as f:
    f.write("""

extension PatchPipeline {
    convenience init(sandboxEvaluator: PatchSandboxEvaluator) {
        self.init(
            targetSelector: PatchTargetSelector(),
            strategyLibrary: PatchStrategyLibrary(),
            impactPredictor: RepositoryChangeImpactAnalyzer(),
            maximumStrategiesPerTarget: 3,
            sandboxEvaluator: sandboxEvaluator
        )
    }
}

extension WorkflowRetriever {
    func retrieve(
        goal: Goal,
        taskContext: TaskContext,
        worldState: WorldState,
        workflowIndex: WorkflowIndex
    ) -> ParameterizedWorkflow? {
        return self.retrieve(
            goal: goal, 
            taskContext: taskContext, 
            worldState: worldState, 
            workflowIndex: workflowIndex, 
            memoryStore: UnifiedMemoryStore(), 
            selectedStrategy: .testDefault
        )
    }
}

""")
