import re
import os

filepath = 'Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift'
with open(filepath, 'r') as f:
    content = f.read()

# Fix ExperimentManager
content = content.replace("runner: ParallelRunner(),\n            ranker: PatchRanker(),\n            repositoryIndexer: RepositoryIndexer()", 
"runner: ParallelRunner(workspaceRunner: WorkspaceRunner(), repositoryIndexer: RepositoryIndexer()),\n            ranker: PatchRanker(comparator: ResultComparator()),\n            repositoryIndexer: RepositoryIndexer()")


with open(filepath, 'w') as f:
    f.write(content)
