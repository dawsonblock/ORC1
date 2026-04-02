import os

def replace_all(path, old, new):
    if not os.path.exists(path):
        return
    with open(path, "r") as f:
        content = f.read()
    if old in content:
        content = content.replace(old, new)
        with open(path, "w") as f:
            f.write(content)

replace_all("Tests/OracleOSTests/Core/ReasoningEngineTests.swift", "UnifiedMemoryStore()", "UnifiedMemoryStore(appMemory: InMemoryStrategyMemory())")
replace_all("Tests/OracleOSTests/Core/ReasoningEngineTests.swift", "MainPlanner(reasoningThreshold: 0.25)", "MainPlanner(repositoryIndexer: RepositoryIndexer(processAdapter: DefaultProcessAdapter()), impactAnalyzer: RepositoryChangeImpactAnalyzer(), reasoningThreshold: 0.25)")
replace_all("Tests/OracleOSTests/Core/ReasoningEngineTests.swift", "MainPlanner(workflowIndex: workflowIndex, reasoningThreshold: 0)", "MainPlanner(repositoryIndexer: RepositoryIndexer(processAdapter: DefaultProcessAdapter()), impactAnalyzer: RepositoryChangeImpactAnalyzer(), workflowIndex: workflowIndex, reasoningThreshold: 0)")

replace_all("Tests/OracleOSTests/Strategy/StrategyScopedLLMPlanTests.swift", "UnifiedMemoryStore()", "UnifiedMemoryStore(appMemory: InMemoryStrategyMemory())")
replace_all("Tests/OracleOSTests/Strategy/StrategyScopedLLMPlanTests.swift", "PlanGenerator(\n            reasoningEngine: engine,\n            planEvaluator: evaluator\n        )", "PlanGenerator(\n            reasoningEngine: engine,\n            planEvaluator: evaluator,\n            operatorRegistry: OperatorRegistry(),\n            osPlanner: OSPlanner(),\n            codePlanner: CodePlanner()\n        )")

replace_all("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "UnifiedMemoryStore()", "UnifiedMemoryStore(appMemory: InMemoryStrategyMemory())")
replace_all("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "RepositoryIndexer()", "RepositoryIndexer(processAdapter: DefaultProcessAdapter())")

replace_all("Tests/OracleOSEvals/EvalTestCompatibility.swift", "RepositoryIndexer()", "RepositoryIndexer(processAdapter: DefaultProcessAdapter())")
