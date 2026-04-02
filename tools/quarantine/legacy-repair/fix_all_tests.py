with open("Tests/OracleOSTests/TestCompatibility/TestAPICompatibility.swift", "a") as f:
    f.write("""

extension RepositoryIndexer {
    convenience init() {
        self.init(processAdapter: DefaultProcessAdapter())
    }
}

extension WorkspaceRunner {
    convenience init() {
        self.init(processAdapter: DefaultProcessAdapter())
    }
}

extension CodePlanner {
    convenience init() {
        self.init(
            repositoryIndexer: RepositoryIndexer(),
            impactAnalyzer: RepositoryChangeImpactAnalyzer()
        )
    }
    
    convenience init(workflowIndex: WorkflowIndex) {
        self.init(
            repositoryIndexer: RepositoryIndexer(),
            impactAnalyzer: RepositoryChangeImpactAnalyzer(),
            workflowIndex: workflowIndex
        )
    }
}

extension ExperimentManager {
    convenience init() {
        self.init(
            runner: ParallelRunner(),
            ranker: PatchRanker(),
            repositoryIndexer: RepositoryIndexer()
        )
    }
}
""")
