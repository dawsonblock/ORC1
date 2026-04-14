import Foundation
import Testing

@testable import OracleOS

@Suite("Experiment Result Isolation")
struct ExperimentResultIsolationTests {

    @Test("Experiment results remain sandbox-only across codable round-trips")
    func experimentResultsRoundTripAsSandboxOnly() throws {
        let result = makeResult(selected: true)

        #expect(result.executionContext == .sandbox)
        #expect(result.committedToWorkspace == false)

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExperimentResult.self, from: data)

        #expect(decoded.executionContext == .sandbox)
        #expect(decoded.committedToWorkspace == false)
        #expect(decoded.selected == true)
        #expect(
            decoded.sandboxEvidence?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
        #expect(decoded.sandboxEvidence?.commitCoordinatorMutation == false)
        #expect(
            decoded.sandboxMetadata?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
        #expect(decoded.sandboxMetadata?.cleanup.succeeded == true)
    }

    @Test("Selection updates preserve sandbox proof metadata")
    func selectionUpdatePreservesSandboxProofMetadata() {
        let result = makeResult(selected: false)
        let updated = result.with(selected: true, promptDiagnostics: nil)

        #expect(updated.selected == true)
        #expect(updated.executionContext == .sandbox)
        #expect(updated.committedToWorkspace == false)
        #expect(
            updated.sandboxEvidence?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
        #expect(
            updated.sandboxMetadata?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
    }

    @Test("Diagnostics keep sandbox context separate from committed runtime state")
    func diagnosticsPreserveSandboxOnlyMetadata() {
        let result = makeResult(selected: true)
        let candidate = DiagnosticsExperimentCandidate(result: result)
        let summary = DiagnosticsExperimentSummary(
            id: result.experimentID,
            candidateCount: 1,
            selectedCandidateID: candidate.id,
            winningSandboxPath: candidate.sandboxPath,
            executionContext: candidate.executionContext,
            committedToWorkspace: candidate.committedToWorkspace,
            succeededCandidateCount: 1,
            candidates: [candidate]
        )

        #expect(candidate.executionContext == "sandbox")
        #expect(candidate.committedToWorkspace == false)
        #expect(summary.executionContext == "sandbox")
        #expect(summary.committedToWorkspace == false)
    }

    @Test("Trace-only diagnostics fallback stays sandbox-only")
    func traceOnlyDiagnosticsFallbackStaysSandboxOnly() {
        let traceEvents = [
            TraceEvent(
                sessionID: "session",
                taskID: nil,
                stepID: 1,
                toolName: "oracle_experiment_search",
                actionName: "oracle_experiment_search",
                verified: true,
                success: true,
                commandSummary: "trace-only experiment",
                experimentID: "exp-1",
                candidateID: "candidate-1",
                sandboxPath: "/tmp/oracle/workspace/.oracle/experiments/exp-1/candidate-1",
                selectedCandidate: true,
                elapsedMs: 5
            )
        ]

        let summaries = RuntimeDiagnosticsBuilder().experimentSummaries(traceEvents: traceEvents)

        #expect(summaries.count == 1)
        #expect(summaries.first?.executionContext == "sandbox")
        #expect(summaries.first?.committedToWorkspace == false)
    }

    private func makeResult(selected: Bool) -> ExperimentResult {
        ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: "candidate-1",
                title: "sandbox patch",
                summary: "prove sandbox-only metadata",
                workspaceRelativePath: "Sources/Example.swift",
                content: "// sandbox-only"
            ),
            sandboxPath: "/tmp/oracle/experiments/exp-1/candidate-1",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "ok",
                    stderr: "",
                    elapsedMs: 10,
                    workspaceRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                    category: .test,
                    summary: "sandbox tests passed"
                )
            ],
            diffSummary: "1 file changed",
            architectureRiskScore: 0.1,
            selected: selected,
            sandboxEvidence: ExperimentSandboxEvidence(
                resolvedSandboxRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                canonicalWorkspaceRoot: "/tmp/oracle/workspace",
                candidatePaths: ["Sources/Example.swift"],
                executedCommands: ["swift test"],
                cleanupOutcome: ExperimentCleanupOutcome(
                    worktreeRemoved: true,
                    branchDeleted: true
                )
            ),
            sandboxMetadata: SandboxExecutionMetadata(
                canonicalWorkspaceRoot: "/tmp/oracle/workspace",
                resolvedSandboxRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                candidateRelativePath: "Sources/Example.swift",
                attemptedPaths: [
                    "Sources/Example.swift",
                    "/tmp/oracle/experiments/exp-1/candidate-1/Sources/Example.swift",
                ],
                commandsRun: ["swift test"],
                cleanup: SandboxCleanupOutcome(
                    succeeded: true,
                    removedWorktree: true,
                    removedBranch: true
                )
            )
        )
    }
}
