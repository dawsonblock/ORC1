import re

path = "Sources/OracleOS/Execution/Experiments/PatchExperimentRunner.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("private let strategyLibrary: PatchStrategyLibrary", "private let strategyLibrary: PatchStrategyLibrary\n    private let ranker: PatchRanker")
code = code.replace("strategyLibrary: PatchStrategyLibrary = .shared", "strategyLibrary: PatchStrategyLibrary = .shared,\n        ranker: PatchRanker")
code = code.replace("self.strategyLibrary = strategyLibrary", "self.strategyLibrary = strategyLibrary\n        self.ranker = ranker")
code = code.replace("let ranker = PatchRanker()", "let ranker = self.ranker")

with open(path, "w") as f:
    f.write(code)
