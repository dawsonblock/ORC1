import re
for path in ["Tests/OracleOSEvals/EvalTestCompatibility.swift", "Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift"]:
    with open(path, "r") as f:
        text = f.read()

    text = text.replace("RepositoryChangeImpactAnalyzer(processAdapter: DefaultProcessAdapter())", "RepositoryChangeImpactAnalyzer()")

    with open(path, "w") as f:
        f.write(text)
