import Foundation
import Testing
@testable import OracleOS

@Suite("Experiment Sandbox Evidence")
struct ExperimentSandboxEvidenceTests {
    @Test("Sandbox evidence round-trips with explicit isolation flags")
    func sandboxEvidenceRoundTrip() throws {
        let result = ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "candidate-1",
                title: "sandbox patch",
                summary: "prove isolation metadata",
                workspaceRelativePath: "Sources/Example.swift",
                content: "// sandbox-only"
            ),
            sandboxPath: "/tmp/oracle/experiments/exp-1/candidate-1",
            commandResults: [],
            diffSummary: "1 file changed",
            architectureRiskScore: 0.1,
            sandboxEvidence: ExperimentSandboxEvidence(
                resolvedSandboxRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                canonicalWorkspaceRoot: "/tmp/oracle/workspace",
                candidatePaths: ["Sources/Example.swift"],
                executedCommands: ["swift test"],
                cleanupOutcome: ExperimentCleanupOutcome(worktreeRemoved: true, branchDeleted: true)
            )
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExperimentResult.self, from: data)

        #expect(decoded.sandboxEvidence?.commitCoordinatorMutation == false)
        #expect(decoded.sandboxEvidence?.approvalStorePromotion == false)
        #expect(decoded.sandboxEvidence?.liveRuntimeStateMutation == false)
        #expect(decoded.sandboxEvidence?.workspaceWritebackOutsideSandbox == false)
        #expect(decoded.sandboxEvidence?.cleanupOutcome.worktreeRemoved == true)
    }
}
