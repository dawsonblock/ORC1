import re

with open("Sources/OracleOS/Execution/Experiments/ExperimentManager.swift", "r") as f:
    code = f.read()

code = code.replace("private let ranker: PatchRanker", "private let ranker: PatchRanker\n    private let repositoryIndexer: RepositoryIndexer")
code = code.replace("ranker: PatchRanker,", "ranker: PatchRanker,\n        repositoryIndexer: RepositoryIndexer,")
code = code.replace("self.ranker = ranker", "self.ranker = ranker\n        self.repositoryIndexer = repositoryIndexer")

with open("Sources/OracleOS/Execution/Experiments/ExperimentManager.swift", "w") as f:
    f.write(code)
