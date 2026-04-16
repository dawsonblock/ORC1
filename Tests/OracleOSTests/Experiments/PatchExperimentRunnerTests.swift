import Foundation
import Testing

@testable import OracleOS

@Suite("Patch Experiment Runner")
struct PatchExperimentRunnerTests {

    @Test("Experiment runner plans with applicable strategies")
    func runnerPlansWithStrategies() {
        let runner = PatchExperimentRunner()
        let plan = runner.plan(
            errorSignature: "Fatal error: Index out of range",
            faultLocationConfidence: 0.8,
            candidates: [makeCandidatePatch()],
            snapshot: nil as RepositorySnapshot? as RepositorySnapshot? as RepositorySnapshot?
        )

        #expect(!plan.strategies.isEmpty)
        #expect(plan.faultLocationConfidence == 0.8)
        #expect(!plan.candidates.isEmpty)
    }

    @Test("Experiment plan captures error signature")
    func planCapturesErrorSignature() {
        let runner = PatchExperimentRunner()
        let plan = runner.plan(
            errorSignature: "nil unwrap",
            faultLocationConfidence: 0.6,
            candidates: [],
            snapshot: nil as RepositorySnapshot? as RepositorySnapshot? as RepositorySnapshot?
        )

        #expect(plan.errorSignature == "nil unwrap")
    }

    @Test("Experiment runner orders pipeline candidates by evaluation metadata")
    func runnerOrdersPipelineCandidatesDeterministically() {
        let runner = PatchExperimentRunner()
        let plan = runner.plan(
            errorSignature: "index out of range",
            faultLocationConfidence: 0.2,
            candidates: [
                CandidatePatch(
                    id: "candidate-zeta",
                    title: "Zeta patch",
                    summary: "higher path name but cleaner fix",
                    workspaceRelativePath: "Sources/Zeta.swift",
                    content: "// clean fix",
                    faultLocationConfidence: 0.6,
                    evaluation: CandidatePatchEvaluation(
                        testsFixed: 2,
                        regressions: 0,
                        dependencyImpact: 0,
                        origin: "boundary_fix on Sources/Zeta.swift"
                    )
                ),
                CandidatePatch(
                    id: "candidate-alpha",
                    title: "Alpha patch",
                    summary: "regressive fix",
                    workspaceRelativePath: "Sources/Alpha.swift",
                    content: "// regressive fix",
                    faultLocationConfidence: 0.4,
                    evaluation: CandidatePatchEvaluation(
                        testsFixed: 1,
                        regressions: 1,
                        dependencyImpact: 0,
                        origin: "boundary_fix on Sources/Alpha.swift"
                    )
                ),
            ],
            snapshot: nil as RepositorySnapshot? as RepositorySnapshot? as RepositorySnapshot?
        )

        #expect(plan.candidates.first?.workspaceRelativePath == "Sources/Zeta.swift")
        #expect(plan.faultLocationConfidence == 0.6)
    }

    @Test("Experiment runner builds ExperimentSpec from plan and snapshot")
    func runnerBuildsExperimentSpecFromPlan() {
        let runner = PatchExperimentRunner()
        let candidate = makeCandidatePatch()
        let snapshot = makeSnapshot(buildTool: .swiftPackage)
        let plan = runner.plan(
            errorSignature: "nil unwrap",
            faultLocationConfidence: 0.7,
            candidates: [candidate],
            snapshot: snapshot
        )

        let spec = runner.experimentSpec(for: plan, snapshot: snapshot)

        #expect(spec.goalDescription == "nil unwrap")
        #expect(spec.workspaceRoot == snapshot.workspaceRoot)
        #expect(spec.candidates == plan.candidates)
        #expect(spec.buildCommand?.summary == "swift build")
        #expect(spec.testCommand?.summary == "swift test")
    }

    @Test("Patch ranking signals compute composite score")
    func patchRankingSignalsComputeCompositeScore() {
        let signals = PatchRankingSignals(
            faultLocationConfidence: 0.9,
            patchComplexity: 0.2,
            coverageImpact: 0.7,
            memorySuccessPatterns: 0.5
        )

        #expect(signals.compositeScore > 0)
        // compositeScore = 0.4*0.9 + 0.25*(1-0.2) + 0.2*0.7 + 0.15*0.5
        let expected = 0.4 * 0.9 + 0.25 * 0.8 + 0.2 * 0.7 + 0.15 * 0.5
        #expect(abs(signals.compositeScore - expected) < 0.001)
    }

    @Test("Ranked results resolve ties with canonical candidate ordering")
    func rankResultsResolveTiesDeterministically() {
        let runner = PatchExperimentRunner()

        let firstPass = runner.rankResults(
            [
                makeTiedResult(
                    candidateID: "aaa-candidate",
                    title: "Zeta patch",
                    workspaceRelativePath: "Sources/Zeta.swift"
                ),
                makeTiedResult(
                    candidateID: "zzz-candidate",
                    title: "Alpha patch",
                    workspaceRelativePath: "Sources/Alpha.swift"
                ),
            ],
            faultLocationConfidence: 0.8,
            memoryStore: nil
        )

        let secondPass = runner.rankResults(
            [
                makeTiedResult(
                    candidateID: "zzz-candidate",
                    title: "Alpha patch",
                    workspaceRelativePath: "Sources/Alpha.swift"
                ),
                makeTiedResult(
                    candidateID: "aaa-candidate",
                    title: "Zeta patch",
                    workspaceRelativePath: "Sources/Zeta.swift"
                ),
            ],
            faultLocationConfidence: 0.8,
            memoryStore: nil
        )

        #expect(firstPass.first?.candidate.workspaceRelativePath == "Sources/Alpha.swift")
        #expect(secondPass.first?.candidate.workspaceRelativePath == "Sources/Alpha.swift")
        #expect(firstPass.first?.selected == true)
        #expect(firstPass.dropFirst().allSatisfy { !$0.selected })
        #expect(secondPass.first?.selected == true)
        #expect(secondPass.dropFirst().allSatisfy { !$0.selected })
    }

    @Test("Ranked results preserve sandbox proof metadata")
    func rankResultsPreserveSandboxProofMetadata() {
        let runner = PatchExperimentRunner()
        let results = [
            ExperimentResult(
                experimentID: "exp-1",
                candidate: CandidatePatch(
                    id: "candidate-1",
                    title: "Sandbox patch",
                    summary: "Preserve experiment proof metadata",
                    workspaceRelativePath: "Sources/Calculator.swift",
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
                sandboxEvidence: ExperimentSandboxEvidence(
                    resolvedSandboxRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                    canonicalWorkspaceRoot: "/tmp/oracle/workspace",
                    candidatePaths: ["Sources/Calculator.swift"],
                    executedCommands: ["swift test"],
                    cleanupOutcome: ExperimentCleanupOutcome(
                        worktreeRemoved: true,
                        branchDeleted: true
                    )
                ),
                sandboxMetadata: SandboxExecutionMetadata(
                    canonicalWorkspaceRoot: "/tmp/oracle/workspace",
                    resolvedSandboxRoot: "/tmp/oracle/experiments/exp-1/candidate-1",
                    candidateRelativePath: "Sources/Calculator.swift",
                    attemptedPaths: [
                        "Sources/Calculator.swift",
                        "/tmp/oracle/experiments/exp-1/candidate-1/Sources/Calculator.swift",
                    ],
                    commandsRun: ["swift test"],
                    cleanup: SandboxCleanupOutcome(
                        succeeded: true,
                        removedWorktree: true,
                        removedBranch: true
                    )
                )
            )
        ]

        let ranked = runner.rankResults(results, faultLocationConfidence: 0.8, memoryStore: nil)

        #expect(ranked.count == 1)
        #expect(ranked[0].selected == true)
        #expect(ranked[0].executionContext == .sandbox)
        #expect(ranked[0].committedToWorkspace == false)
        #expect(
            ranked[0].sandboxEvidence?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
        #expect(
            ranked[0].sandboxMetadata?.resolvedSandboxRoot
                == "/tmp/oracle/experiments/exp-1/candidate-1")
    }

    private func makeCandidatePatch() -> CandidatePatch {
        CandidatePatch(
            id: "patch-1",
            title: "Fix boundary condition",
            summary: "Guard against out-of-bounds array access",
            workspaceRelativePath: "Sources/Calculator.swift",
            content: "+guard index < array.count else { return }"
        )
    }

    private func makeSnapshot(buildTool: BuildTool) -> RepositorySnapshot {
        RepositorySnapshot(
            id: "snapshot-1",
            workspaceRoot: "/tmp/workspace",
            buildTool: buildTool,
            files: [RepositoryFile(path: "Sources/Calculator.swift", isDirectory: false)],
            symbolGraph: SymbolGraph(),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: false
        )
    }

    private func makeTiedResult(
        candidateID: String,
        title: String,
        workspaceRelativePath: String
    ) -> ExperimentResult {
        ExperimentResult(
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: candidateID,
                title: title,
                summary: "Deterministic tie-break coverage",
                workspaceRelativePath: workspaceRelativePath,
                content: "+// deterministic tie-break"
            ),
            sandboxPath: "/tmp/\(candidateID)",
            commandResults: [
                CommandResult(
                    succeeded: true,
                    exitCode: 0,
                    stdout: "ok",
                    stderr: "",
                    elapsedMs: 20,
                    workspaceRoot: "/tmp/workspace",
                    category: .test,
                    summary: "swift test"
                )
            ],
            diffSummary: "1 file changed",
            architectureRiskScore: 0.1
        )
    }
}
