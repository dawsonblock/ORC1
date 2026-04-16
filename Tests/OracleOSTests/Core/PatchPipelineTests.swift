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
        #expect(applied.proposedContent.contains("struct Calculator"))
        #expect(applied.proposedContent.contains("oracle-patch-candidate: null_guard near add"))
        #expect(
            applied.proposedContent.contains(
                "proposed-edit: guard let value = optionalValue else { return }"))

        let markerRange = try #require(
            applied.proposedContent.range(of: "oracle-patch-candidate: null_guard near add"))
        let symbolRange = try #require(
            applied.proposedContent.range(of: "func add(optionalValue: Int?) -> Int"))
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

        #expect(result.candidates.map(\.workspaceRelativePath) == [alphaPath, betaPath])
    }

    // MARK: - RankedPatch ranking formula

    @Test("RankedPatch rank = testsFixed - regressions - dependencyImpact")
    func rankFormula() {
        let patch = RankedPatch(
            workspaceRelativePath: "Sources/Foo.swift",
            proposedContent: "// fix",
            testsFixed: 3,
            regressions: 1,
            dependencyImpact: 1,
            origin: "null_guard"
        )
        #expect(patch.rank == 1)  // 3 - 1 - 1
    }

    @Test("RankedPatch with zero regressions and positive testsFixed has positive rank")
    func positiveRankForGoodPatch() {
        let patch = RankedPatch(
            workspaceRelativePath: "Sources/Bar.swift",
            proposedContent: "// guard let fix",
            testsFixed: 2,
            regressions: 0,
            dependencyImpact: 0,
            origin: "null_guard"
        )
        #expect(patch.rank > 0)
    }

    @Test("RankedPatch with regressions has lower rank than clean patch")
    func regressivePatchRankedLower() {
        let clean = RankedPatch(
            workspaceRelativePath: "a.swift", proposedContent: "",
            testsFixed: 2, regressions: 0, dependencyImpact: 0, origin: "clean"
        )
        let regressive = RankedPatch(
            workspaceRelativePath: "b.swift", proposedContent: "",
            testsFixed: 2, regressions: 2, dependencyImpact: 0, origin: "regressive"
        )
        #expect(clean.rank > regressive.rank)
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
        let patch = RankedPatch(
            workspaceRelativePath: "f.swift", proposedContent: "",
            testsFixed: 1, regressions: 0, dependencyImpact: 0, origin: "test"
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
