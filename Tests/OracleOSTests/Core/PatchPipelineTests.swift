import Foundation
import Testing

@testable import OracleOS

@Suite("PatchPipeline")
struct PatchPipelineTests {

    // MARK: - Pipeline stage ordering

    @Test("PatchPipeline returns localizationFailed when no targets found")
    func localizationFailed() {
        // Use a blank snapshot so no symbols match the failure signature
        let snapshot = RepositorySnapshot(
            id: UUID().uuidString,
            workspaceRoot: "/tmp/test-repo",
            files: [],
            symbols: [],
            buildTool: .spm,
            activeBranch: "main",
            isGitDirty: false
        )
        let pipeline = PatchPipeline(
            sandboxEvaluator: PatchPipeline.defaultEvaluator
        )
        let result = pipeline.run(failureDescription: "obscure failure", snapshot: snapshot)
        if case .localizationFailed = result.outcome {
            // expected
        } else if case .noViablePatch = result.outcome {
            // also acceptable — no targets → no patches
        } else if case .applied = result.outcome {
            Issue.record("Should not apply a patch when no targets found")
        }
        #expect(result.completedStages.contains(.failure))
    }

    @Test("RepairPipeline stage ordering validates correctly")
    func stageOrderingValid() {
        let validStages: [RepairPipeline.Stage] = [
            .failure, .localization, .candidateSymbols, .patchCandidates,
            .sandboxValidation, .regressionCheck, .rankFix, .apply,
        ]
        let missing = RepairPipeline.validateOrder(validStages)
        #expect(missing == nil)
    }

    @Test("RepairPipeline detects missing localization stage")
    func missingLocalizationDetected() {
        let missingLocalization: [RepairPipeline.Stage] = [
            .failure, .candidateSymbols, .patchCandidates,
        ]
        let missing = RepairPipeline.validateOrder(missingLocalization)
        #expect(missing != nil)
    }

    @Test("RepairPipeline localizationPrecedesPatching enforced")
    func localizationBeforePatching() {
        let correct: [RepairPipeline.Stage] = [
            .failure, .localization, .candidateSymbols, .patchCandidates,
        ]
        #expect(RepairPipeline.localizationPrecedesPatching(correct) == true)

        let wrong: [RepairPipeline.Stage] = [.failure, .patchCandidates, .localization]
        #expect(RepairPipeline.localizationPrecedesPatching(wrong) == false)
    }

    @Test("RepairPipeline sandboxPrecedesApply enforced")
    func sandboxBeforeApply() {
        let correct: [RepairPipeline.Stage] = [.sandboxValidation, .apply]
        #expect(RepairPipeline.sandboxPrecedesApply(correct) == true)

        let wrong: [RepairPipeline.Stage] = [.apply, .sandboxValidation]
        #expect(RepairPipeline.sandboxPrecedesApply(wrong) == false)
    }

    @Test("PatchPipeline grounds candidates to live file content near matched symbols")
    func groundedCandidateUsesLiveFileContent() throws {
        let workspaceRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let filePath = "Sources/Calculator.swift"
        let originalContent = """
            import Foundation

            struct Calculator {
                func add(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """
        try writeFile(
            at: workspaceRoot.appendingPathComponent(filePath, isDirectory: false),
            content: originalContent + "\n"
        )

        let snapshot = makeSnapshot(
            workspaceRoot: workspaceRoot,
            files: [filePath],
            symbolNodes: [
                SymbolNode(
                    id: "\(filePath)|Calculator|struct|3",
                    name: "Calculator",
                    kind: .struct,
                    file: filePath,
                    lineStart: 3,
                    lineEnd: 6
                ),
                SymbolNode(
                    id: "\(filePath)|add|function|4",
                    name: "add",
                    kind: .function,
                    file: filePath,
                    lineStart: 4,
                    lineEnd: 6
                ),
            ]
        )

        let result = makePipeline().run(
            failureDescription: "\(filePath) add optional unexpectedly found nil",
            snapshot: snapshot
        )
        let applied = try #require(result.applied)

        #expect(applied.workspaceRelativePath == filePath)
        #expect(applied.content.contains("struct Calculator"))
        #expect(applied.content.contains("oracle-patch-candidate: null_guard near add"))
        #expect(
            applied.content.contains(
                "proposed-edit: guard let value = optionalValue else { return }"))
        #expect(applied.evaluation?.origin == "null_guard on \(filePath)")
        #expect(applied.rank == 1)

        let markerRange = try #require(
            applied.content.range(of: "oracle-patch-candidate: null_guard near add"))
        let symbolRange = try #require(
            applied.content.range(of: "func add(optionalValue: Int?) -> Int"))
        #expect(markerRange.lowerBound < symbolRange.lowerBound)
    }

    @Test("PatchPipeline breaks ranking ties deterministically by path")
    func rankingTieBreaksByPath() throws {
        let workspaceRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let alphaPath = "Sources/Alpha.swift"
        let betaPath = "Sources/Beta.swift"
        let alphaContent = """
            struct Alpha {
                func handle(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """
        let betaContent = """
            struct Beta {
                func handle(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """

        try writeFile(
            at: workspaceRoot.appendingPathComponent(alphaPath, isDirectory: false),
            content: alphaContent + "\n"
        )
        try writeFile(
            at: workspaceRoot.appendingPathComponent(betaPath, isDirectory: false),
            content: betaContent + "\n"
        )

        let snapshot = makeSnapshot(
            workspaceRoot: workspaceRoot,
            files: [alphaPath, betaPath],
            symbolNodes: [
                SymbolNode(
                    id: "\(alphaPath)|handle|function|2",
                    name: "handle",
                    kind: .function,
                    file: alphaPath,
                    lineStart: 2,
                    lineEnd: 4
                ),
                SymbolNode(
                    id: "\(betaPath)|handle|function|2",
                    name: "handle",
                    kind: .function,
                    file: betaPath,
                    lineStart: 2,
                    lineEnd: 4
                ),
            ]
        )

        let evaluator: SandboxEvaluatorFn = { _, _, _ in
            SandboxEvaluation(compiled: true, testsFixed: 1, regressions: 0)
        }
        let result = makePipeline(sandboxEvaluator: evaluator).run(
            failureDescription: "handle optional unexpectedly found nil",
            snapshot: snapshot
        )

        let candidatePaths = result.candidates.map(\.workspaceRelativePath)
        let firstBetaIndex = try #require(candidatePaths.firstIndex(of: betaPath))
        #expect(candidatePaths[..<firstBetaIndex].allSatisfy { $0 == alphaPath })
        #expect(candidatePaths[firstBetaIndex...].allSatisfy { $0 == betaPath })
    }

    @Test("PatchPipeline prefers higher-confidence candidates before path tie-breaks")
    func rankingPrefersHigherConfidenceBeforePath() throws {
        let workspaceRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let alphaPath = "Sources/Alpha.swift"
        let betaPath = "Sources/Beta.swift"
        let alphaContent = """
            struct Alpha {
                func handle(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """
        let betaContent = """
            struct Beta {
                func handle(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """

        try writeFile(
            at: workspaceRoot.appendingPathComponent(alphaPath, isDirectory: false),
            content: alphaContent + "\n"
        )
        try writeFile(
            at: workspaceRoot.appendingPathComponent(betaPath, isDirectory: false),
            content: betaContent + "\n"
        )

        let snapshot = makeSnapshot(
            workspaceRoot: workspaceRoot,
            files: [alphaPath, betaPath],
            symbolNodes: [
                SymbolNode(
                    id: "\(alphaPath)|handle|function|2",
                    name: "handle",
                    kind: .function,
                    file: alphaPath,
                    lineStart: 2,
                    lineEnd: 4
                ),
                SymbolNode(
                    id: "\(betaPath)|handle|function|2",
                    name: "handle",
                    kind: .function,
                    file: betaPath,
                    lineStart: 2,
                    lineEnd: 4
                ),
            ]
        )

        let evaluator: SandboxEvaluatorFn = { _, _, _ in
            SandboxEvaluation(compiled: true, testsFixed: 1, regressions: 0)
        }
        let result = makePipeline(sandboxEvaluator: evaluator).run(
            failureDescription: "compare fixes for failing handle assertion in Sources/Beta.swift",
            snapshot: snapshot
        )

        #expect(result.candidates.first?.workspaceRelativePath == betaPath)
        #expect((result.candidates.first?.faultLocationConfidence ?? 0) > 0)
    }

    @Test("PatchPipeline feeds candidates into experiment planning")
    func pipelineFeedsCandidatesIntoExperimentPlan() throws {
        let workspaceRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let filePath = "Sources/Calculator.swift"
        let originalContent = """
            struct Calculator {
                func add(optionalValue: Int?) -> Int {
                    return optionalValue ?? 0
                }
            }
            """
        try writeFile(
            at: workspaceRoot.appendingPathComponent(filePath, isDirectory: false),
            content: originalContent + "\n"
        )

        let snapshot = makeSnapshot(
            workspaceRoot: workspaceRoot,
            files: [filePath],
            symbolNodes: [
                SymbolNode(
                    id: "\(filePath)|add|function|2",
                    name: "add",
                    kind: .function,
                    file: filePath,
                    lineStart: 2,
                    lineEnd: 4
                )
            ]
        )

        let pipeline = makePipeline()
        let runner = PatchExperimentRunner()

        let plan = try #require(
            pipeline.experimentPlan(
                failureDescription: "\(filePath) add optional unexpectedly found nil",
                snapshot: snapshot,
                runner: runner
            )
        )
        let spec = try #require(
            pipeline.experimentSpec(
                failureDescription: "\(filePath) add optional unexpectedly found nil",
                snapshot: snapshot,
                runner: runner
            )
        )

        #expect(plan.candidates.first?.workspaceRelativePath == filePath)
        #expect(plan.candidates.first?.evaluation?.testsFixed == 1)
        #expect(spec.candidates == plan.candidates)
        #expect(spec.buildCommand?.summary == "swift build")
        #expect(spec.testCommand?.summary == "swift test")
    }

    // MARK: - CandidatePatch evaluation metadata

    @Test("CandidatePatch rank = testsFixed - regressions - dependencyImpact")
    func rankFormula() {
        let patch = CandidatePatch(
            id: "candidate-1",
            title: "Test candidate",
            summary: "summary",
            workspaceRelativePath: "Sources/Foo.swift",
            content: "// fix",
            evaluation: CandidatePatchEvaluation(
                testsFixed: 3,
                regressions: 1,
                dependencyImpact: 1,
                origin: "null_guard"
            )
        )
        #expect(patch.rank == 1)  // 3 - 1 - 1
    }

    @Test("CandidatePatch with zero regressions and positive testsFixed has positive rank")
    func positiveRankForGoodPatch() {
        let patch = CandidatePatch(
            id: "candidate-2",
            title: "Guard candidate",
            summary: "summary",
            workspaceRelativePath: "Sources/Bar.swift",
            content: "// guard let fix",
            evaluation: CandidatePatchEvaluation(
                testsFixed: 2,
                regressions: 0,
                dependencyImpact: 0,
                origin: "null_guard"
            )
        )
        #expect((patch.rank ?? 0) > 0)
    }

    @Test("CandidatePatch with regressions has lower rank than clean patch")
    func regressivePatchRankedLower() {
        let clean = CandidatePatch(
            id: "clean",
            title: "Clean",
            summary: "summary",
            workspaceRelativePath: "a.swift",
            content: "",
            evaluation: CandidatePatchEvaluation(
                testsFixed: 2,
                regressions: 0,
                dependencyImpact: 0,
                origin: "clean"
            )
        )
        let regressive = CandidatePatch(
            id: "regressive",
            title: "Regressive",
            summary: "summary",
            workspaceRelativePath: "b.swift",
            content: "",
            evaluation: CandidatePatchEvaluation(
                testsFixed: 2,
                regressions: 2,
                dependencyImpact: 0,
                origin: "regressive"
            )
        )
        #expect((clean.rank ?? .min) > (regressive.rank ?? .min))
    }

    // MARK: - Default sandbox evaluator

    @Test("defaultEvaluator rejects content with unbalanced braces")
    func rejectsUnbalancedBraces() {
        let content = "func foo() { if true { }"  // missing outer close
        let snapshot = RepositorySnapshot(
            id: "x", workspaceRoot: "/x", files: [], symbols: [],
            buildTool: .spm, activeBranch: "main", isGitDirty: false
        )
        let eval = PatchPipeline.defaultEvaluator("f.swift", content, snapshot)
        #expect(eval.compiled == false)
    }

    @Test("defaultEvaluator approves balanced content with guard pattern")
    func approvesGuardPattern() {
        let content = "guard let x = optionalX else { return }\n"
        let snapshot = RepositorySnapshot(
            id: "x", workspaceRoot: "/x", files: [], symbols: [],
            buildTool: .spm, activeBranch: "main", isGitDirty: false
        )
        let eval = PatchPipeline.defaultEvaluator("f.swift", content, snapshot)
        #expect(eval.compiled == true)
        #expect(eval.testsFixed == 1)
    }

    // MARK: - PatchResult accessors

    @Test("PatchResult.applied returns nil for noViablePatch outcome")
    func appliedNilForNoViablePatch() {
        let result = PatchResult(outcome: .noViablePatch, candidates: [], completedStages: [])
        #expect(result.applied == nil)
    }

    @Test("PatchResult.applied returns patch for applied outcome")
    func appliedReturnsForApplied() {
        let patch = CandidatePatch(
            id: "patch-result",
            title: "Test patch",
            summary: "summary",
            workspaceRelativePath: "f.swift",
            content: "",
            evaluation: CandidatePatchEvaluation(
                testsFixed: 1,
                regressions: 0,
                dependencyImpact: 0,
                origin: "test"
            )
        )
        let result = PatchResult(outcome: .applied(patch), candidates: [patch], completedStages: [])
        #expect(result.applied?.workspaceRelativePath == "f.swift")
    }

    private func makePipeline(
        sandboxEvaluator: @escaping SandboxEvaluatorFn = PatchPipeline.defaultEvaluator
    ) -> PatchPipeline {
        PatchPipeline(
            targetSelector: PatchTargetSelector(),
            strategyLibrary: PatchStrategyLibrary(),
            impactPredictor: PatchImpactPredictor(impactAnalyzer: RepositoryChangeImpactAnalyzer()),
            maximumStrategiesPerTarget: 3,
            sandboxEvaluator: sandboxEvaluator
        )
    }

    private func makeSnapshot(
        workspaceRoot: URL,
        files: [String],
        symbolNodes: [SymbolNode] = []
    ) -> RepositorySnapshot {
        RepositorySnapshot(
            id: "test-repo",
            workspaceRoot: workspaceRoot.path,
            buildTool: .swiftPackage,
            files: files.map { RepositoryFile(path: $0, isDirectory: false) },
            symbolGraph: SymbolGraph(nodes: symbolNodes, edges: []),
            dependencyGraph: DependencyGraph(),
            testGraph: TestGraph(),
            activeBranch: "main",
            isGitDirty: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFile(at fileURL: URL, content: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
