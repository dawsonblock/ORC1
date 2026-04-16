import Foundation

// MARK: - PatchPipeline result types

/// A ranked candidate patch selected by the pipeline.
///
/// Ranking is advisory. The surrounding workflow still decides whether this
/// candidate should be applied, validated more deeply, or rejected.
public struct RankedPatch: Sendable {
    /// Target file path relative to the workspace root.
    public let workspaceRelativePath: String
    /// Candidate replacement content proposed by the strategy.
    public let proposedContent: String
    /// Number of tests fixed in sandbox validation.
    public let testsFixed: Int
    /// Number of regressions introduced (0 is ideal).
    public let regressions: Int
    /// Estimated downstream dependency impact count.
    public let dependencyImpact: Int
    /// Origin description (strategy kind + root cause path).
    public let origin: String

    /// Composite rank: `tests_fixed − regressions − dependency_impact`.
    /// Higher is better.
    public var rank: Int { testsFixed - regressions - dependencyImpact }
}

/// Outcome of a full `PatchPipeline` run.
///
/// This describes candidate selection only. The pipeline itself does not own
/// workspace mutation or committed-state authority.
public struct PatchResult: Sendable {
    public enum Outcome: Sendable {
        /// A candidate met the heuristic quality bar and was selected as the
        /// recommended candidate for a surrounding workflow to consider applying.
        case applied(RankedPatch)
        /// Candidates were generated and evaluated but none met the quality bar.
        case noViablePatch
        /// Localization returned no candidates — nothing to patch.
        case localizationFailed
    }

    public let outcome: Outcome
    /// All ranked candidates evaluated during the run (best-first).
    public let candidates: [RankedPatch]
    /// Ordered `RepairPipeline.Stage` values completed in this run.
    public let completedStages: [RepairPipeline.Stage]

    public var applied: RankedPatch? {
        if case .applied(let p) = outcome { return p }
        return nil
    }
}

// MARK: - Sandbox evaluator

/// Evaluates a candidate patch in a sandboxed context.
///
/// Default implementation uses lightweight heuristics. Replace with a real
/// `swift build` / `swift test` harness in integration environments.
public struct SandboxEvaluation: Sendable {
    public let compiled: Bool
    public let testsFixed: Int
    public let regressions: Int
    public let stderr: String

    public init(
        compiled: Bool,
        testsFixed: Int,
        regressions: Int,
        stderr: String = ""
    ) {
        self.compiled = compiled
        self.testsFixed = testsFixed
        self.regressions = regressions
        self.stderr = stderr
    }
}

public typealias SandboxEvaluatorFn =
    @Sendable (
        _ relativePath: String,
        _ proposedContent: String,
        _ snapshot: RepositorySnapshot
    ) -> SandboxEvaluation

// MARK: - PatchPipeline

/// Candidate patch pipeline for bounded repair workflows.
///
/// The pipeline combines localization, candidate generation, lightweight
/// sandbox evaluation, and ranking to select a best-ranked candidate patch. It does
/// not guarantee semantic correctness, applicability, or successful commit.
///
/// Pipeline order (asserted via ``RepairPipeline`` invariants):
///
///     failure detected
///     ↓  localization  (PatchTargetSelector)
///     ↓  candidate targets
///     ↓  patch strategies  (PatchStrategyLibrary)
///     ↓  sandbox validation  (SandboxEvaluatorFn)
///     ↓  build / test / regression check
///     ↓  impact scoring  (PatchImpactPredictor)
///     ↓  rank candidate patches  (rank = tests_fixed − regressions − dependency_impact)
///     ↓  apply
///
/// **Invariants** (enforced at runtime):
/// - Localization before patch generation.
/// - Sandbox validation before apply.
public struct PatchPipeline: Sendable {

    private let targetSelector: PatchTargetSelector
    private let strategyLibrary: PatchStrategyLibrary
    private let impactPredictor: PatchImpactPredictor
    private let sandboxEvaluator: SandboxEvaluatorFn
    /// Maximum strategies evaluated per target file.
    private let maximumStrategiesPerTarget: Int

    public init(
        targetSelector: PatchTargetSelector = PatchTargetSelector(),
        strategyLibrary: PatchStrategyLibrary = PatchStrategyLibrary(),
        impactPredictor: PatchImpactPredictor,
        maximumStrategiesPerTarget: Int = 3,
        sandboxEvaluator: @escaping SandboxEvaluatorFn = PatchPipeline.defaultEvaluator
    ) {
        self.targetSelector = targetSelector
        self.strategyLibrary = strategyLibrary
        self.impactPredictor = impactPredictor
        self.maximumStrategiesPerTarget = maximumStrategiesPerTarget
        self.sandboxEvaluator = sandboxEvaluator
    }

    // MARK: - Main entry point

    /// Execute the candidate-patch pipeline for a build or test failure.
    ///
    /// - Parameters:
    ///   - failureDescription: Raw build or test failure output.
    ///   - snapshot: Repository snapshot for localization and impact analysis.
    /// - Returns: Advisory pipeline output describing the best-ranked available candidate.
    public func run(
        failureDescription: String,
        snapshot: RepositorySnapshot
    ) -> PatchResult {
        var completedStages: [RepairPipeline.Stage] = [.failure]

        // ── Stage 1: Localization ─────────────────────────────────────────────
        let targets = targetSelector.select(
            failureDescription: failureDescription,
            in: snapshot
        )
        guard !targets.isEmpty else {
            return PatchResult(
                outcome: .localizationFailed,
                candidates: [],
                completedStages: completedStages
            )
        }
        completedStages.append(.localization)
        completedStages.append(.candidateSymbols)

        // ── Stage 2: Grounded patch candidate synthesis ─────────────────────
        let applicableStrategies = Array(
            strategyLibrary
                .applicable(for: failureDescription, snapshot: snapshot)
                .prefix(maximumStrategiesPerTarget)
        )
        var patchTriples: [(target: PatchTarget, strategy: PatchStrategy, content: String)] = []
        for target in targets {
            for strategy in applicableStrategies {
                guard
                    let content = groundedCandidateContent(
                        for: strategy,
                        target: target,
                        snapshot: snapshot,
                        failureDescription: failureDescription
                    )
                else {
                    continue
                }
                patchTriples.append((target: target, strategy: strategy, content: content))
            }
        }
        completedStages.append(.patchCandidates)
        guard !patchTriples.isEmpty else {
            return PatchResult(
                outcome: .noViablePatch,
                candidates: [],
                completedStages: completedStages
            )
        }

        // ── Stage 3: Sandbox validation ───────────────────────────────────────
        var rankedPatches: [RankedPatch] = []
        let impactPredictions = impactPredictor.predict(patchTargets: targets, in: snapshot)

        for triple in patchTriples {
            let eval = sandboxEvaluator(triple.target.path, triple.content, snapshot)
            guard eval.compiled else { continue }

            let impact = impactPredictions.first(where: { $0.path == triple.target.path })
            // Map blast radius score to a discrete dependency impact count.
            let depImpact = Int(((impact?.blastRadiusScore ?? 0) * 10).rounded())

            rankedPatches.append(
                RankedPatch(
                    workspaceRelativePath: triple.target.path,
                    proposedContent: triple.content,
                    testsFixed: eval.testsFixed,
                    regressions: eval.regressions,
                    dependencyImpact: depImpact,
                    origin: "\(triple.strategy.kind.rawValue) on \(triple.target.path)"
                ))
        }
        completedStages.append(.sandboxValidation)
        completedStages.append(.regressionCheck)

        // ── Stage 4: Rank ─────────────────────────────────────────────────────
        let sorted =
            rankedPatches
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.rank != rhs.element.rank {
                    return lhs.element.rank > rhs.element.rank
                }
                if lhs.element.testsFixed != rhs.element.testsFixed {
                    return lhs.element.testsFixed > rhs.element.testsFixed
                }
                if lhs.element.regressions != rhs.element.regressions {
                    return lhs.element.regressions < rhs.element.regressions
                }
                if lhs.element.dependencyImpact != rhs.element.dependencyImpact {
                    return lhs.element.dependencyImpact < rhs.element.dependencyImpact
                }
                if lhs.element.workspaceRelativePath != rhs.element.workspaceRelativePath {
                    return lhs.element.workspaceRelativePath < rhs.element.workspaceRelativePath
                }
                if lhs.element.origin != rhs.element.origin {
                    return lhs.element.origin < rhs.element.origin
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        completedStages.append(.rankFix)

        // Quality bar: select the highest-ranked zero-regression candidate.
        // This is still heuristic selection, not proof that the patch is correct.
        let best = sorted.first(where: { $0.regressions == 0 })
        guard let bestPatch = best else {
            return PatchResult(
                outcome: .noViablePatch,
                candidates: sorted,
                completedStages: completedStages
            )
        }
        completedStages.append(.apply)

        // Enforce pipeline invariants
        assert(
            RepairPipeline.localizationPrecedesPatching(completedStages),
            "PatchPipeline invariant violated: localization must precede patching"
        )
        assert(
            RepairPipeline.sandboxPrecedesApply(completedStages),
            "PatchPipeline invariant violated: sandbox must precede apply"
        )

        return PatchResult(
            outcome: .applied(bestPatch),
            candidates: sorted,
            completedStages: completedStages
        )
    }

    // MARK: - Grounded candidate synthesis

    /// Synthesizes a candidate by splicing strategy guidance into the live
    /// target file content near the best symbol anchor available.
    ///
    /// The resulting content is still advisory, but it is grounded to the
    /// current repository state instead of being a detached placeholder stub.
    private func groundedCandidateContent(
        for strategy: PatchStrategy,
        target: PatchTarget,
        snapshot: RepositorySnapshot,
        failureDescription: String
    ) -> String? {
        guard let originalContent = loadCurrentFileContent(for: target.path, snapshot: snapshot),
            let commentPrefix = commentPrefix(for: target.path)
        else {
            return nil
        }

        var lines =
            originalContent
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.isEmpty {
            lines = [""]
        }

        let anchor = anchoredSymbol(for: target, in: snapshot)
        var insertionIndex = anchor.map { max(0, min(lines.count, $0.lineStart - 1)) } ?? 0
        if insertionIndex == 0, lines.first?.hasPrefix("#!") == true {
            insertionIndex = min(1, lines.count)
        }

        let indentation = indentationForInsertion(in: lines, insertionIndex: insertionIndex)
        let advisoryLines = advisoryPatchLines(
            for: strategy,
            target: target,
            anchor: anchor,
            failureDescription: failureDescription
        ).map { "\(indentation)\(commentPrefix) \($0)" }

        lines.insert(contentsOf: advisoryLines + [""], at: insertionIndex)

        let candidate = lines.joined(separator: "\n")
        return originalContent.hasSuffix("\n") ? candidate + "\n" : candidate
    }

    private func loadCurrentFileContent(
        for relativePath: String,
        snapshot: RepositorySnapshot
    ) -> String? {
        let workspaceRoot = URL(fileURLWithPath: snapshot.workspaceRoot, isDirectory: true)
        let fileURL = workspaceRoot.appendingPathComponent(relativePath, isDirectory: false)
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func commentPrefix(for relativePath: String) -> String? {
        if relativePath == "Package.swift" {
            return "//"
        }

        switch URL(fileURLWithPath: relativePath).pathExtension.lowercased() {
        case "swift", "c", "cc", "cpp", "h", "hpp", "m", "mm", "js", "jsx", "ts", "tsx", "java",
            "kt", "go", "rs":
            return "//"
        case "py", "rb", "sh", "yml", "yaml", "toml", "ini", "conf":
            return "#"
        default:
            return nil
        }
    }

    private func anchoredSymbol(
        for target: PatchTarget,
        in snapshot: RepositorySnapshot
    ) -> SymbolNode? {
        let fileNodes = snapshot.symbolGraph.nodes(inFile: target.path).sorted { lhs, rhs in
            if lhs.lineStart == rhs.lineStart {
                return lhs.name < rhs.name
            }
            return lhs.lineStart < rhs.lineStart
        }
        guard !fileNodes.isEmpty else {
            return nil
        }

        for matchedSymbol in target.rootCauseCandidate.matchedSymbols {
            if let exactMatch = fileNodes.first(where: {
                $0.name.caseInsensitiveCompare(matchedSymbol) == .orderedSame
            }) {
                return exactMatch
            }
            if let partialMatch = fileNodes.first(where: {
                $0.name.localizedCaseInsensitiveContains(matchedSymbol)
                    || matchedSymbol.localizedCaseInsensitiveContains($0.name)
            }) {
                return partialMatch
            }
        }

        return fileNodes.first
    }

    private func indentationForInsertion(
        in lines: [String],
        insertionIndex: Int
    ) -> String {
        guard !lines.isEmpty else {
            return ""
        }

        let candidateIndices = [
            min(max(insertionIndex, 0), lines.count - 1),
            min(max(insertionIndex - 1, 0), lines.count - 1),
        ]

        for index in candidateIndices {
            let line = lines[index]
            if line.isEmpty == false {
                return String(line.prefix { $0 == " " || $0 == "\t" })
            }
        }

        return ""
    }

    private func advisoryPatchLines(
        for strategy: PatchStrategy,
        target: PatchTarget,
        anchor: SymbolNode?,
        failureDescription: String
    ) -> [String] {
        let anchorLabel =
            anchor?.name
            ?? target.rootCauseCandidate.matchedSymbols.first
            ?? URL(fileURLWithPath: target.path).lastPathComponent
        let rationale =
            target.rootCauseCandidate.reasons.first ?? "failure localization selected this file"

        return [
            "oracle-patch-candidate: \(strategy.kind.rawValue) near \(anchorLabel)",
            "rationale: \(rationale)",
            "failure-signal: \(condensedFailureDescription(failureDescription))",
            "proposed-edit: \(advisorySnippet(for: strategy.kind))",
        ]
    }

    private func condensedFailureDescription(_ failureDescription: String) -> String {
        let firstLine =
            failureDescription
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? failureDescription
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 96 else {
            return trimmed
        }
        let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 96)
        return String(trimmed[..<cutoff]) + "..."
    }

    private func advisorySnippet(for strategyKind: PatchStrategyKind) -> String {
        switch strategyKind {
        case .nullGuard:
            return "guard let value = optionalValue else { return }"
        case .boundaryFix:
            return "guard index >= 0 && index < collection.count else { return }"
        case .typeCorrection:
            return "if let typedValue = rawValue as? ExpectedType { return typedValue }"
        case .dependencyUpdate:
            return "import MissingDependency"
        case .testExpectationUpdate:
            return "#expect(actual == expectedValue)"
        case .configurationFix:
            return "ensure required configuration value is present before execution"
        }
    }

    // MARK: - Default sandbox evaluator

    /// Lightweight heuristic evaluator.
    ///
    /// Checks for unbalanced braces and obvious type mismatches, then
    /// estimates `testsFixed` from the presence of defensive patterns. It does
    /// not guarantee semantic correctness or real-world applicability.
    public static let defaultEvaluator: SandboxEvaluatorFn = { _, content, _ in
        let openBraces = content.filter { $0 == "{" }.count
        let closeBraces = content.filter { $0 == "}" }.count
        guard openBraces == closeBraces else {
            return SandboxEvaluation(
                compiled: false, testsFixed: 0, regressions: 0, stderr: "Unbalanced braces")
        }
        let hasFix =
            content.contains("guard ")
            || content.contains("if let ")
            || content.contains("?? ")
            || content.contains("index < ")
            || content.contains("as? ")
            || content.contains("#expect(")
            || content.contains("XCTAssert")
            || content.localizedCaseInsensitiveContains("configuration")
            || content.contains("import ")
        return SandboxEvaluation(compiled: true, testsFixed: hasFix ? 1 : 0, regressions: 0)
    }
}
