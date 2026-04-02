import os

filepath = 'Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift'
with open(filepath, 'r') as f:
    content = f.read()

# Fix PatchPipeline
content = content.replace("impactPredictor: RepositoryChangeImpactAnalyzer(),", "impactPredictor: PatchImpactPredictor(impactAnalyzer: RepositoryChangeImpactAnalyzer()),")

# Fix WorkflowRetriever return type
content = content.replace("-> ParameterizedWorkflow?", "-> WorkflowMatch?")

# Append new extensions
content += """

extension PatchExperimentRunner {
    convenience init() {
        self.init(
            experimentManager: ExperimentManager(),
            ranker: PatchRanker(comparator: ResultComparator())
        )
    }
}
"""

with open(filepath, 'w') as f:
    f.write(content)
