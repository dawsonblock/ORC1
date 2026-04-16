import Foundation

public struct PatchExperimentResult: Sendable {
    public let candidate: CandidatePatch
    public let strategy: PatchStrategyKind
    public let testsPassed: Bool
    public let buildSucceeded: Bool
    public let coverageImpact: Double
    public let notes: [String]

    public init(
        candidate: CandidatePatch,
        strategy: PatchStrategyKind,
        testsPassed: Bool,
        buildSucceeded: Bool,
        coverageImpact: Double = 0,
        notes: [String] = []
    ) {
        self.candidate = candidate
        self.strategy = strategy
        self.testsPassed = testsPassed
        self.buildSucceeded = buildSucceeded
        self.coverageImpact = coverageImpact
        self.notes = notes
    }

    public var succeeded: Bool {
        testsPassed && buildSucceeded
    }
}

public struct PatchExperimentPlan: Sendable {
    public let errorSignature: String
    public let faultLocationConfidence: Double
    public let candidates: [CandidatePatch]
    public let strategies: [PatchStrategy]

    public init(
        errorSignature: String,
        faultLocationConfidence: Double,
        candidates: [CandidatePatch],
        strategies: [PatchStrategy]
    ) {
        self.errorSignature = errorSignature
        self.faultLocationConfidence = faultLocationConfidence
        self.candidates = candidates
        self.strategies = strategies
    }
}

public final class PatchExperimentRunner: @unchecked Sendable {
    private let experimentManager: ExperimentManager
    private let strategyLibrary: PatchStrategyLibrary
    private let ranker: PatchRanker

    public init(
        experimentManager: ExperimentManager,
        strategyLibrary: PatchStrategyLibrary = .shared,
        ranker: PatchRanker
    ) {
        self.experimentManager = experimentManager
        self.strategyLibrary = strategyLibrary
        self.ranker = ranker
    }

    public func plan(
        errorSignature: String,
        faultLocationConfidence: Double,
        candidates: [CandidatePatch],
        snapshot: RepositorySnapshot?
    ) -> PatchExperimentPlan {
        let orderedCandidates = orderedPlanningCandidates(candidates)
        let applicableStrategies = strategyLibrary.applicable(
            for: errorSignature,
            snapshot: snapshot
        )
        return PatchExperimentPlan(
            errorSignature: errorSignature,
            faultLocationConfidence: max(
                faultLocationConfidence,
                orderedCandidates.first?.faultLocationConfidence ?? 0
            ),
            candidates: orderedCandidates,
            strategies: applicableStrategies
        )
    }

    public func experimentSpec(
        for plan: PatchExperimentPlan,
        snapshot: RepositorySnapshot
    ) -> ExperimentSpec {
        let workspaceURL = URL(fileURLWithPath: snapshot.workspaceRoot, isDirectory: true)
        return ExperimentSpec(
            goalDescription: plan.errorSignature,
            workspaceRoot: snapshot.workspaceRoot,
            candidates: plan.candidates,
            buildCommand: BuildToolDetector.defaultBuildCommand(
                for: snapshot.buildTool,
                workspaceRoot: workspaceURL
            ).map(ExperimentCommandRequest.init(commandSpec:)),
            testCommand: BuildToolDetector.defaultTestCommand(
                for: snapshot.buildTool,
                workspaceRoot: workspaceURL
            ).map(ExperimentCommandRequest.init(commandSpec:))
        )
    }

    public func run(
        spec: ExperimentSpec,
        architectureRiskScore: Double = 0
    ) async throws -> [ExperimentResult] {
        try await experimentManager.run(
            spec: spec,
            architectureRiskScore: architectureRiskScore
        )
    }

    public func rankResults(
        _ results: [ExperimentResult],
        faultLocationConfidence: Double,
        memoryStore: UnifiedMemoryStore?
    ) -> [ExperimentResult] {
        let ranker = self.ranker
        let ranked = ranker.rank(results)

        return ranked.enumerated().map { index, result in
            result.with(selected: index == 0, promptDiagnostics: result.promptDiagnostics)
        }
    }

    private func orderedPlanningCandidates(_ candidates: [CandidatePatch]) -> [CandidatePatch] {
        candidates.enumerated()
            .sorted { lhs, rhs in
                if planningRank(lhs.element) != planningRank(rhs.element) {
                    return planningRank(lhs.element) > planningRank(rhs.element)
                }
                if planningTestsFixed(lhs.element) != planningTestsFixed(rhs.element) {
                    return planningTestsFixed(lhs.element) > planningTestsFixed(rhs.element)
                }
                if planningRegressions(lhs.element) != planningRegressions(rhs.element) {
                    return planningRegressions(lhs.element) < planningRegressions(rhs.element)
                }
                if planningDependencyImpact(lhs.element) != planningDependencyImpact(rhs.element) {
                    return planningDependencyImpact(lhs.element)
                        < planningDependencyImpact(rhs.element)
                }
                if lhs.element.faultLocationConfidence != rhs.element.faultLocationConfidence {
                    return (lhs.element.faultLocationConfidence ?? 0)
                        > (rhs.element.faultLocationConfidence ?? 0)
                }
                if lhs.element.complexity != rhs.element.complexity {
                    return (lhs.element.complexity ?? 0) < (rhs.element.complexity ?? 0)
                }
                if lhs.element.workspaceRelativePath != rhs.element.workspaceRelativePath {
                    return lhs.element.workspaceRelativePath < rhs.element.workspaceRelativePath
                }
                if lhs.element.title != rhs.element.title {
                    return lhs.element.title < rhs.element.title
                }
                if lhs.element.summary != rhs.element.summary {
                    return lhs.element.summary < rhs.element.summary
                }
                if lhs.element.content != rhs.element.content {
                    return lhs.element.content < rhs.element.content
                }
                if lhs.element.hypothesis != rhs.element.hypothesis {
                    return (lhs.element.hypothesis ?? "") < (rhs.element.hypothesis ?? "")
                }
                if lhs.element.strategyKind != rhs.element.strategyKind {
                    return (lhs.element.strategyKind ?? "") < (rhs.element.strategyKind ?? "")
                }
                if planningOrigin(lhs.element) != planningOrigin(rhs.element) {
                    return planningOrigin(lhs.element) < planningOrigin(rhs.element)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func planningRank(_ candidate: CandidatePatch) -> Int {
        candidate.rank ?? .min
    }

    private func planningTestsFixed(_ candidate: CandidatePatch) -> Int {
        candidate.evaluation?.testsFixed ?? 0
    }

    private func planningRegressions(_ candidate: CandidatePatch) -> Int {
        candidate.evaluation?.regressions ?? .max
    }

    private func planningDependencyImpact(_ candidate: CandidatePatch) -> Int {
        candidate.evaluation?.dependencyImpact ?? .max
    }

    private func planningOrigin(_ candidate: CandidatePatch) -> String {
        candidate.evaluation?.origin ?? ""
    }
}
