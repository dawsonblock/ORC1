import Foundation

// MCPDispatch+Architecture.swift — Architecture review tool implementations.
//
// Covers: oracle_architecture_review, oracle_candidate_review

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
            return ToolResult(success: true, data: archReviewToDict(review))

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
            return ToolResult(success: true, data: archReviewToDict(review))

        default:
            return ToolResult(success: false, error: "Unknown architecture tool: \(request.name)")
        }
    }

    private static func archReviewToDict(_ review: ArchitectureReview) -> [String: Any] {
        var d: [String: Any] = [
            "triggered": review.triggered,
            "risk_score": review.riskScore,
            "affected_modules": review.affectedModules,
        ]
        d["findings"] = review.findings.map { f -> [String: Any] in
            var fd: [String: Any] = [
                "title": f.title,
                "summary": f.summary,
                "severity": f.severity.rawValue,
                "risk_score": f.riskScore,
                "affected_modules": f.affectedModules,
            ]
            if !f.evidence.isEmpty { fd["evidence"] = f.evidence }
            return fd
        }
        if let proposal = review.refactorProposal {
            d["refactor_proposal"] = [
                "id": proposal.id,
                "title": proposal.title,
                "summary": proposal.summary,
                "steps": proposal.steps,
                "risk_score": proposal.riskScore,
            ]
        }
        return d
    }
}
