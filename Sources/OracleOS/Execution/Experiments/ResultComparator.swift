import Foundation

public struct ResultComparator: Sendable {
    public init() {}

    public func sort(_ results: [ExperimentResult]) -> [ExperimentResult] {
        results.enumerated()
            .sorted { lhs, rhs in
                if orderedBefore(lhs.element, rhs.element) {
                    return true
                }
                if orderedBefore(rhs.element, lhs.element) {
                    return false
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func orderedBefore(_ lhs: ExperimentResult, _ rhs: ExperimentResult) -> Bool {
        if lhs.succeeded != rhs.succeeded {
            return lhs.succeeded && !rhs.succeeded
        }
        if lhs.architectureRiskScore != rhs.architectureRiskScore {
            return lhs.architectureRiskScore < rhs.architectureRiskScore
        }
        let lhsCriticalFindings = criticalFindingCount(lhs.architectureFindings)
        let rhsCriticalFindings = criticalFindingCount(rhs.architectureFindings)
        if lhsCriticalFindings != rhsCriticalFindings {
            return lhsCriticalFindings < rhsCriticalFindings
        }
        let lhsTouched = touchedFileCount(lhs.diffSummary)
        let rhsTouched = touchedFileCount(rhs.diffSummary)
        if lhsTouched != rhsTouched {
            return lhsTouched < rhsTouched
        }
        let lhsDiff = lhs.diffSummary.count
        let rhsDiff = rhs.diffSummary.count
        if lhsDiff != rhsDiff {
            return lhsDiff < rhsDiff
        }
        if lhs.elapsedMs != rhs.elapsedMs {
            return lhs.elapsedMs < rhs.elapsedMs
        }
        if candidateOrderedBefore(lhs.candidate, rhs.candidate) {
            return true
        }
        if candidateOrderedBefore(rhs.candidate, lhs.candidate) {
            return false
        }
        return false
    }

    private func touchedFileCount(_ diffSummary: String) -> Int {
        diffSummary
            .split(separator: "\n")
            .filter { $0.contains("|") }
            .count
    }

    private func criticalFindingCount(_ findings: [ArchitectureFinding]) -> Int {
        findings.filter { $0.severity == .critical }.count
    }

    private func candidateOrderedBefore(_ lhs: CandidatePatch, _ rhs: CandidatePatch) -> Bool {
        if let comparison = compare(lhs.workspaceRelativePath, rhs.workspaceRelativePath) {
            return comparison
        }
        if let comparison = compare(lhs.title, rhs.title) {
            return comparison
        }
        if let comparison = compare(lhs.summary, rhs.summary) {
            return comparison
        }
        if let comparison = compare(lhs.content, rhs.content) {
            return comparison
        }
        if let comparison = compare(lhs.hypothesis ?? "", rhs.hypothesis ?? "") {
            return comparison
        }
        if let comparison = compare(lhs.strategyKind ?? "", rhs.strategyKind ?? "") {
            return comparison
        }
        if let comparison = compare(lhs.faultLocationConfidence, rhs.faultLocationConfidence) {
            return comparison
        }
        if let comparison = compare(lhs.complexity, rhs.complexity) {
            return comparison
        }
        if let comparison = compare(explicitCandidateID(lhs.id), explicitCandidateID(rhs.id)) {
            return comparison
        }
        return false
    }

    private func explicitCandidateID(_ candidateID: String) -> String {
        UUID(uuidString: candidateID) == nil ? candidateID : ""
    }

    private func compare(_ lhs: String, _ rhs: String) -> Bool? {
        guard lhs != rhs else { return nil }
        return lhs < rhs
    }

    private func compare(_ lhs: Double?, _ rhs: Double?) -> Bool? {
        switch (lhs, rhs) {
        case (let lhsValue?, let rhsValue?) where lhsValue != rhsValue:
            return lhsValue < rhsValue
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        default:
            return nil
        }
    }
}
