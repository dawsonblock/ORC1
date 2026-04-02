import re
with open("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "r") as f:
    text = f.read()

replacement = """extension MainPlanner {
    convenience init() {
        self.init(
            repositoryIndexer: RepositoryIndexer(),
            impactAnalyzer: RepositoryChangeImpactAnalyzer()
        )
    }

    func nextStep("""

text = text.replace("extension MainPlanner {\n    func nextStep(", replacement)

with open("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "w") as f:
    f.write(text)

