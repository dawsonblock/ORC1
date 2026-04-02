import os

path = "Sources/OracleOS/Runtime/RuntimeBootstrap.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("let planner = MainPlanner()", """let impactAnalyzer = RepositoryChangeImpactAnalyzer()
        let planner = MainPlanner(
            repositoryIndexer: repositoryIndexer,
            impactAnalyzer: impactAnalyzer
        )""")
code = code.replace("let memoryStore = UnifiedMemoryStore()", "let memoryStore = UnifiedMemoryStore(appMemory: EventMemory(eventStore: eventStore))")

code = code.replace("let experimentManager = ExperimentManager()", """let parallelRunner = ParallelRunner(
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer
        )
        let patchRanker = PatchRanker(comparator: PatchResultComparator())
        let experimentManager = ExperimentManager(
            runner: parallelRunner,
            ranker: patchRanker,
            repositoryIndexer: repositoryIndexer
        )""")

code = code.replace("let browserPageStateBuilder = BrowserPageStateBuilder()", "let browserPageStateBuilder = BrowserPageStateBuilder(controller: browserController)")

with open(path, "w") as f:
    f.write(code)
