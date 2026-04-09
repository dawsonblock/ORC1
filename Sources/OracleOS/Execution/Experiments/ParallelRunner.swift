import Foundation

public final class ParallelRunner: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner
    private let repositoryIndexer: RepositoryIndexer
    private let architectureEngine: ArchitectureEngine

    public init(
        workspaceRunner: WorkspaceRunner,
        repositoryIndexer: RepositoryIndexer,
        architectureEngine: ArchitectureEngine = ArchitectureEngine()
    ) {
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
        self.architectureEngine = architectureEngine
    }

    public func run(
        spec: ExperimentSpec,
        experimentsRoot: URL,
        architectureRiskScore: Double
    ) async throws -> [ExperimentResult] {
        let workspaceRoot = URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true)
        let canonicalWorkspaceRoot = workspaceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let workspaceRunner = self.workspaceRunner
        let repositoryIndexer = self.repositoryIndexer
        let architectureEngine = self.architectureEngine

        return try await withThrowingTaskGroup(of: ExperimentResult.self) { group in
            for candidate in spec.candidates {
                group.addTask {
                    let sandbox = try WorktreeSandbox.create(
                        experimentID: spec.id,
                        candidateID: candidate.id,
                        workspaceRoot: workspaceRoot,
                        experimentsRoot: experimentsRoot,
                        adapter: workspaceRunner.processAdapter
                    )
                    let buildCommand = spec.buildCommand?.materializedForSandbox(workspaceRoot: sandbox.sandboxPath)
                        ?? BuildToolDetector.defaultBuildCommand(
                            for: BuildToolDetector.detect(at: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)),
                            workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                        )
                    let testCommand = spec.testCommand?.materializedForSandbox(workspaceRoot: sandbox.sandboxPath)
                        ?? BuildToolDetector.defaultTestCommand(
                            for: BuildToolDetector.detect(at: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)),
                            workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                        )

                    do {
                        try sandbox.apply(candidate)

                        var results: [CommandResult] = []
                        if let buildCommand {
                            results.append(try await workspaceRunner.execute(spec: buildCommand))
                        }
                        if results.allSatisfy(\.succeeded), let testCommand {
                            results.append(try await workspaceRunner.execute(spec: testCommand))
                        }

                        let diffSummary = sandbox.diffSummary(using: workspaceRunner.processAdapter)
                        let candidateSnapshot = repositoryIndexer.indexIfNeeded(
                            workspaceRoot: URL(fileURLWithPath: sandbox.sandboxPath, isDirectory: true)
                        )
                        let architectureReview = architectureEngine.reviewCandidatePatch(
                            goalDescription: spec.goalDescription,
                            snapshot: candidateSnapshot,
                            candidate: candidate,
                            diffSummary: diffSummary
                        )
                        let effectiveArchitectureRisk = max(architectureRiskScore, architectureReview.riskScore)
                        let cleanupOutcome = sandbox.cleanup(using: workspaceRunner.processAdapter)

                        return ExperimentResult(
                            experimentID: spec.id,
                            candidate: candidate,
                            sandboxPath: sandbox.sandboxPath,
                            commandResults: results,
                            diffSummary: diffSummary,
                            architectureRiskScore: effectiveArchitectureRisk,
                            architectureFindings: architectureReview.findings,
                            refactorProposalID: architectureReview.refactorProposal?.id,
                            sandboxEvidence: ExperimentSandboxEvidence(
                                resolvedSandboxRoot: sandbox.resolvedSandboxRoot,
                                canonicalWorkspaceRoot: canonicalWorkspaceRoot,
                                candidatePaths: [candidate.workspaceRelativePath],
                                executedCommands: [buildCommand?.summary, testCommand?.summary].compactMap { $0 },
                                cleanupOutcome: cleanupOutcome
                            )
                        )
                    } catch {
                        _ = sandbox.cleanup(using: workspaceRunner.processAdapter)
                        throw error
                    }
                }
            }

            var collected: [ExperimentResult] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }
    }
}
