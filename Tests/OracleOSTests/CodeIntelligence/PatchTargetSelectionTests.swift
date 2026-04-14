import Foundation
import Testing

@testable import OracleOS

@Suite("Patch Target Selection")
struct PatchTargetSelectionTests {

    @Test("Patch strategy library returns applicable strategies")
    func strategyLibraryReturnsApplicable() {
        let library = PatchStrategyLibrary.shared
        let strategies = library.applicable(for: "index out of range", snapshot: nil)
        #expect(!strategies.isEmpty)
        #expect(strategies.first?.kind == .boundaryFix)
    }

    @Test("BoundaryFix applies to index-related errors")
    func boundaryFixApplies() {
        #expect(BoundaryFix.isApplicable(errorSignature: "Fatal error: Index out of range"))
        #expect(!BoundaryFix.isApplicable(errorSignature: "nil unwrap failure"))
    }

    @Test("NullGuard applies to nil-related errors")
    func nullGuardApplies() {
        #expect(NullGuard.isApplicable(errorSignature: "Unexpectedly found nil while unwrapping"))
        #expect(!NullGuard.isApplicable(errorSignature: "Index out of range"))
    }

    @Test("TypeCorrection applies to type mismatch errors")
    func typeCorrectionApplies() {
        #expect(
            TypeCorrection.isApplicable(
                errorSignature: "Cannot convert value of type Int to String"))
        #expect(!TypeCorrection.isApplicable(errorSignature: "file not found"))
    }

    @Test("DependencyUpdate applies to module resolution errors")
    func dependencyUpdateApplies() {
        #expect(DependencyUpdate.isApplicable(errorSignature: "No module named 'Foundation'"))
        #expect(!DependencyUpdate.isApplicable(errorSignature: "nil unwrap"))
    }

    @Test("ConfigFix applies to configuration errors")
    func configFixApplies() {
        #expect(ConfigFix.isApplicable(errorSignature: "Invalid configuration setting"))
        #expect(!ConfigFix.isApplicable(errorSignature: "index out of range"))
    }

    @Test("ExperimentResultRanker ranks succeeded results higher")
    func resultRankerPrefersSuccess() {
        let ranker = ExperimentResultRanker(
            patchRanker: PatchRanker(comparator: ResultComparator()))
        let succeeded = makeResult(id: "pass", succeeded: true)
        let failed = makeResult(id: "fail", succeeded: false)

        let ranked = ranker.rank(results: [failed, succeeded])
        // Succeeded results should rank higher
        if ranked.count >= 2 {
            #expect(ranked.first?.succeeded == true)
        }
    }

    @Test("ExperimentResultRanker resolves equal signals with canonical ordering")
    func resultRankerBreaksSignalTiesDeterministically() {
        let ranker = ExperimentResultRanker(
            patchRanker: PatchRanker(comparator: ResultComparator()))

        let firstPass = ranker.rank(
            results: [
                makeResult(
                    id: "aaa-candidate",
                    succeeded: true,
                    title: "Zeta patch",
                    workspaceRelativePath: "Sources/Zeta.swift"
                ),
                makeResult(
                    id: "zzz-candidate",
                    succeeded: true,
                    title: "Alpha patch",
                    workspaceRelativePath: "Sources/Alpha.swift"
                ),
            ],
            faultLocationConfidence: 0.8,
            memorySuccessPatterns: 0.5
        )

        let secondPass = ranker.rank(
            results: [
                makeResult(
                    id: "zzz-candidate",
                    succeeded: true,
                    title: "Alpha patch",
                    workspaceRelativePath: "Sources/Alpha.swift"
                ),
                makeResult(
                    id: "aaa-candidate",
                    succeeded: true,
                    title: "Zeta patch",
                    workspaceRelativePath: "Sources/Zeta.swift"
                ),
            ],
            faultLocationConfidence: 0.8,
            memorySuccessPatterns: 0.5
        )

        #expect(firstPass.first?.candidate.workspaceRelativePath == "Sources/Alpha.swift")
        #expect(secondPass.first?.candidate.workspaceRelativePath == "Sources/Alpha.swift")
    }

    private func makeResult(
        id: String,
        succeeded: Bool,
        title: String = "test patch",
        workspaceRelativePath: String = "Sources/Calculator.swift"
    ) -> ExperimentResult {
        ExperimentResult(
            id: id,
            experimentID: "exp-1",
            candidate: CandidatePatch(
                id: id,
                title: title,
                summary: "A test patch for validation",
                workspaceRelativePath: workspaceRelativePath,
                content: succeeded ? "+guard let x = x else { return }" : "+// broken"
            ),
            sandboxPath: "/tmp/sandbox",
            commandResults: [
                CommandResult(
                    succeeded: succeeded,
                    exitCode: succeeded ? 0 : 1,
                    stdout: succeeded ? "All tests passed" : "Test failed",
                    stderr: "",
                    elapsedMs: 100,
                    workspaceRoot: "/tmp/sandbox",
                    category: .test,
                    summary: succeeded ? "All tests passed" : "Test failed"
                )
            ],
            diffSummary: "1 file changed",
            architectureRiskScore: 0
        )
    }
}
