import re

path = "Sources/OracleOS/Planning/Strategies/CodePlanningStrategy.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),", "repositoryIndexer: RepositoryIndexer,")
code = code.replace("impactAnalyzer: RepositoryChangeImpactAnalyzer = RepositoryChangeImpactAnalyzer(),", "impactAnalyzer: RepositoryChangeImpactAnalyzer,")

with open(path, "w") as f:
    f.write(code)
