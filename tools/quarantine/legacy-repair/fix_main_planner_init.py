import re

path = "Sources/OracleOS/Planning/MainPlanner.swift"
with open(path, "r") as f:
    code = f.read()

# Add to init
code = code.replace(
    "planEvaluator: PlanEvaluator? = nil,",
    "planEvaluator: PlanEvaluator? = nil,\n        repositoryIndexer: RepositoryIndexer,\n        impactAnalyzer: RepositoryChangeImpactAnalyzer,"
)

# Pass to CodePlanner
code = code.replace(
"""
        let resolvedCodePlanner = codePlanner ?? CodePlanner(
            workflowIndex: resolvedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            promptEngine: promptEngine
        )""",
"""
        let resolvedCodePlanner = codePlanner ?? CodePlanner(
            repositoryIndexer: repositoryIndexer,
            impactAnalyzer: impactAnalyzer,
            workflowIndex: resolvedWorkflowIndex,
            workflowRetriever: sharedWorkflowRetriever,
            promptEngine: promptEngine
        )"""
)

with open(path, "w") as f:
    f.write(code)

