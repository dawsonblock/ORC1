path = "Sources/OracleOS/Planning/MainPlanner.swift"
with open(path, "r") as f:
    code = f.read()
old_init = """    public init(
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        planEvaluator: PlanEvaluator? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskLedgerStore? = nil
    ) {"""
new_init = """    public init(
        repositoryIndexer: RepositoryIndexer,
        impactAnalyzer: RepositoryChangeImpactAnalyzer,
        workflowIndex: WorkflowIndex? = nil,
        osPlanner: OSPlanner? = nil,
        codePlanner: CodePlanner? = nil,
        reasoningEngine: ReasoningEngine? = nil,
        planEvaluator: PlanEvaluator? = nil,
        promptEngine: PromptEngine = PromptEngine(),
        reasoningThreshold: Double = 0.6,
        taskGraphStore: TaskLedgerStore? = nil
    ) {"""
code = code.replace(old_init, new_init)
with open(path, "w") as f:
    f.write(code)
