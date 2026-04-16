import Foundation

public struct CandidatePatchEvaluation: Codable, Sendable, Equatable {
    public let testsFixed: Int
    public let regressions: Int
    public let dependencyImpact: Int
    public let origin: String

    public init(
        testsFixed: Int,
        regressions: Int,
        dependencyImpact: Int,
        origin: String
    ) {
        self.testsFixed = testsFixed
        self.regressions = regressions
        self.dependencyImpact = dependencyImpact
        self.origin = origin
    }

    public var rank: Int {
        testsFixed - regressions - dependencyImpact
    }
}

public struct CandidatePatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let workspaceRelativePath: String
    public let content: String
    public let hypothesis: String?
    public let strategyKind: String?
    public let faultLocationConfidence: Double?
    public let complexity: Double?
    public let evaluation: CandidatePatchEvaluation?

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        workspaceRelativePath: String,
        content: String,
        hypothesis: String? = nil,
        strategyKind: String? = nil,
        faultLocationConfidence: Double? = nil,
        complexity: Double? = nil,
        evaluation: CandidatePatchEvaluation? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.content = content
        self.hypothesis = hypothesis
        self.strategyKind = strategyKind
        self.faultLocationConfidence = faultLocationConfidence
        self.complexity = complexity
        self.evaluation = evaluation
    }

    public var rank: Int? {
        evaluation?.rank
    }
}
