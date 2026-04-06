import Foundation

public struct PlanSelection {
    public static func selectBest(
        familyDecision: PlannerDecision?,
        reasoningDecision: PlannerDecision?,
        taskGraphDecision: PlannerDecision? = nil,
        taskContext: TaskContext,
        worldState: WorldState,
        memoryStore: UnifiedMemoryStore
    ) -> PlannerDecision? {
        let memoryInfluence = MemoryRouter(memoryStore: memoryStore).influence(
            for: MemoryQueryContext(taskContext: taskContext, worldState: worldState)
        )
        let memoryBias = MemoryScorer.planBias(influence: memoryInfluence)
        let familyScore = familyDecision.map { sourceConfidence($0.source) + memoryBias }
        let reasoningScore = reasoningDecision.map { $0.planDiagnostics?.candidatePlans.first?.score ?? 0 }
        let taskGraphScore = taskGraphDecision.map { decision -> Double in
            let baseScore = sourceConfidence(decision.source) + memoryBias
            return baseScore + 0.1
        }

        switch (familyDecision, reasoningDecision) {
        case let (family?, reasoning?):
            let resolvedFamilyScore = familyScore ?? sourceConfidence(family.source) + memoryBias
            let resolvedReasoningScore = reasoningScore ?? 0

            if family.source == reasoning.source,
               family.source == .workflow || family.source == .stableGraph {
                return annotate(
                    family,
                    path: .family,
                    reason: .matchingTrustedSource,
                    familyScore: familyScore,
                    reasoningScore: reasoningScore,
                    taskGraphScore: taskGraphScore,
                    memoryBias: memoryBias
                )
            }

            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision,
                    tgScore >= resolvedFamilyScore && tgScore >= resolvedReasoningScore {
                return annotate(
                    tgDecision,
                    path: .taskGraph,
                    reason: .taskGraphWonComparison,
                    familyScore: familyScore,
                    reasoningScore: reasoningScore,
                    taskGraphScore: taskGraphScore,
                    memoryBias: memoryBias
                )
            }

            if family.source == .workflow || family.source == .stableGraph {
                if resolvedFamilyScore >= resolvedReasoningScore {
                    return annotate(
                        family,
                        path: .family,
                        reason: .familyWonComparison,
                        familyScore: familyScore,
                        reasoningScore: reasoningScore,
                        taskGraphScore: taskGraphScore,
                        memoryBias: memoryBias
                    )
                }
                return annotate(
                    reasoning,
                    path: .reasoning,
                    reason: .reasoningWonComparison,
                    familyScore: familyScore,
                    reasoningScore: reasoningScore,
                    taskGraphScore: taskGraphScore,
                    memoryBias: memoryBias
                )
            }
            if resolvedReasoningScore > resolvedFamilyScore {
                return annotate(
                    reasoning,
                    path: .reasoning,
                    reason: .reasoningWonComparison,
                    familyScore: familyScore,
                    reasoningScore: reasoningScore,
                    taskGraphScore: taskGraphScore,
                    memoryBias: memoryBias
                )
            }
            return annotate(
                family,
                path: .family,
                reason: .familyWonComparison,
                familyScore: familyScore,
                reasoningScore: reasoningScore,
                taskGraphScore: taskGraphScore,
                memoryBias: memoryBias
            )
        case let (family?, nil):
            let resolvedFamilyScore = familyScore ?? sourceConfidence(family.source) + memoryBias

            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                if tgScore >= resolvedFamilyScore {
                    return annotate(
                        tgDecision,
                        path: .taskGraph,
                        reason: .taskGraphWonComparison,
                        familyScore: familyScore,
                        reasoningScore: reasoningScore,
                        taskGraphScore: taskGraphScore,
                        memoryBias: memoryBias
                    )
                }
            }
            return annotate(
                family,
                path: .family,
                reason: taskGraphDecision == nil ? .familyOnly : .familyWonComparison,
                familyScore: familyScore,
                reasoningScore: reasoningScore,
                taskGraphScore: taskGraphScore,
                memoryBias: memoryBias
            )
        case let (nil, reasoning?):
            let resolvedReasoningScore = reasoningScore ?? 0

            if let tgScore = taskGraphScore, let tgDecision = taskGraphDecision {
                if tgScore >= resolvedReasoningScore {
                    return annotate(
                        tgDecision,
                        path: .taskGraph,
                        reason: .taskGraphWonComparison,
                        familyScore: familyScore,
                        reasoningScore: reasoningScore,
                        taskGraphScore: taskGraphScore,
                        memoryBias: memoryBias
                    )
                }
            }
            return annotate(
                reasoning,
                path: .reasoning,
                reason: taskGraphDecision == nil ? .reasoningOnly : .reasoningWonComparison,
                familyScore: familyScore,
                reasoningScore: reasoningScore,
                taskGraphScore: taskGraphScore,
                memoryBias: memoryBias
            )
        case (nil, nil):
            guard let taskGraphDecision else { return nil }
            return annotate(
                taskGraphDecision,
                path: .taskGraph,
                reason: .taskGraphOnly,
                familyScore: familyScore,
                reasoningScore: reasoningScore,
                taskGraphScore: taskGraphScore,
                memoryBias: memoryBias
            )
        }
    }

    private static func annotate(
        _ decision: PlannerDecision,
        path: PlanSelectionPath,
        reason: PlanSelectionReason,
        familyScore: Double?,
        reasoningScore: Double?,
        taskGraphScore: Double?,
        memoryBias: Double
    ) -> PlannerDecision {
        let selectedScore: Double
        switch path {
        case .family:
            selectedScore = familyScore ?? sourceConfidence(decision.source)
        case .reasoning:
            selectedScore = reasoningScore ?? 0
        case .taskGraph:
            selectedScore = taskGraphScore ?? sourceConfidence(decision.source)
        }

        let presentPaths: [PlanSelectionPath?] = [
            familyScore.map { _ in .family },
            reasoningScore.map { _ in .reasoning },
            taskGraphScore.map { _ in .taskGraph },
        ]

        let provenance = PlanSelectionProvenance(
            selectedPath: path,
            selectedSource: decision.source,
            selectionReason: reason,
            selectedScore: selectedScore,
            familyScore: familyScore,
            reasoningScore: reasoningScore,
            taskGraphScore: taskGraphScore,
            memoryBiasApplied: memoryBias,
            sourceConfidenceComponent: sourceConfidence(decision.source),
            rejectedPaths: presentPaths.compactMap { $0 }.filter { $0 != path }
        )

        return decision.with(selectionProvenance: provenance)
    }

    private static func sourceConfidence(_ source: PlannerSource) -> Double {
        switch source {
        case .workflow: return 0.9
        case .stableGraph: return 0.75
        case .candidateGraph: return 0.5
        case .exploration: return 0.3
        case .reasoning: return 0.6
        case .llm: return 0.45
        case .recovery: return 0.4
        case .strategy: return 0.95
        }
    }
}
