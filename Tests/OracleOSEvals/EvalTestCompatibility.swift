import Foundation
@testable import OracleOS

extension MainPlanner {
    convenience init() {
        self.init(
            repositoryIndexer: RepositoryIndexer(processAdapter: DefaultProcessAdapter()),
            impactAnalyzer: RepositoryChangeImpactAnalyzer()
        )
    }

    func plan(failure: FailureClass, state: ReasoningPlanningState) -> [RecoveryPlan] {
        RecoveryPlanner().plan(failure: failure, state: state)
    }
}
