import Foundation

// MCPDispatch+Architecture.swift — Architecture review tool implementations.
//
// Covers: oracle_architecture_review, oracle_candidate_review

struct ArchitectureReviewPayload: Encodable {
    let triggered: Bool
    let riskScore: Double
    let affectedModules: [String]
    let findings: [ArchitectureFindingPayload]
    let refactorProposal: RefactorProposalPayload?

    enum CodingKeys: String, CodingKey {
        case triggered
        case riskScore = "risk_score"
        case affectedModules = "affected_modules"
        case findings
        case refactorProposal = "refactor_proposal"
    }
}

struct ArchitectureFindingPayload: Encodable {
    let title: String
    let summary: String
    let severity: String
    let riskScore: Double
    let affectedModules: [String]
    let evidence: [String]?

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case severity
        case riskScore = "risk_score"
        case affectedModules = "affected_modules"
        case evidence
    }
}

struct RefactorProposalPayload: Encodable {
    let id: String
    let title: String
    let summary: String
    let steps: [String]
    let riskScore: Double

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case steps
        case riskScore = "risk_score"
    }
}

extension MCPDispatch {
    @MainActor
    static func dispatchArchitecture(
        _ request: MCPToolRequest,
        container: RuntimeContainer
    ) -> ToolResult {
        switch request.name {

        case MCPToolName.architectureReview:
            guard let goalDescription = request.string("goal_description") else {
                return ToolResult(success: false, error: "goal_description is required for \(MCPToolName.architectureReview)")
            }
            let candidatePaths = request.strings("candidate_paths") ?? []
            let workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let snapshot = container.repositoryIndexer.indexIfNeeded(workspaceRoot: workspaceURL)
            let review = container.architectureEngine.review(
                goalDescription: goalDescription,
                snapshot: snapshot,
                candidatePaths: candidatePaths
            )
            return typedResult(archReviewPayload(review))

        case MCPToolName.candidateReview:
            guard let goalDescription = request.string("goal_description"),
                  let diffSummary = request.string("diff_summary") else {
                return ToolResult(
                    success: false,
                    error: "goal_description and diff_summary are required for \(MCPToolName.candidateReview)"
                )
            }
            guard let candidateValue = request.arguments.objectValue?["candidate"],
                  let obj = candidateValue.objectValue,
                  let title = obj["title"]?.stringValue,
                  let patchSummary = obj["summary"]?.stringValue,
                  let path = obj["workspace_relative_path"]?.stringValue,
                  let content = obj["content"]?.stringValue else {
                return ToolResult(
                    success: false,
                    error: "candidate object with title, summary, workspace_relative_path, and content is required"
                )
            }
            let patch = CandidatePatch(
                title: title,
                summary: patchSummary,
                workspaceRelativePath: path,
                content: content
            )
            let workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let snapshot = container.repositoryIndexer.indexIfNeeded(workspaceRoot: workspaceURL)
            let review = container.architectureEngine.reviewCandidatePatch(
                goalDescription: goalDescription,
                snapshot: snapshot,
                candidate: patch,
                diffSummary: diffSummary
            )
            return typedResult(archReviewPayload(review))

        default:
            return ToolResult(success: false, error: "Unknown architecture tool: \(request.name)")
        }
    }

    private static func archReviewPayload(_ review: ArchitectureReview) -> ArchitectureReviewPayload {
        ArchitectureReviewPayload(
            triggered: review.triggered,
            riskScore: review.riskScore,
            affectedModules: review.affectedModules,
            findings: review.findings.map { finding in
                ArchitectureFindingPayload(
                    title: finding.title,
                    summary: finding.summary,
                    severity: finding.severity.rawValue,
                    riskScore: finding.riskScore,
                    affectedModules: finding.affectedModules,
                    evidence: finding.evidence.isEmpty ? nil : finding.evidence
                )
            },
            refactorProposal: review.refactorProposal.map { proposal in
                RefactorProposalPayload(
                    id: proposal.id,
                    title: proposal.title,
                    summary: proposal.summary,
                    steps: proposal.steps,
                    riskScore: proposal.riskScore
                )
            }
        )
    }
}
