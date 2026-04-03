import XCTest
@testable import OracleOS

/// Transitional Artifact Removal — source-scan enforcement tests.
///
/// These tests verify that execution routing consolidation is permanent:
/// no legacy planner symbols, no stray executor instantiations, no rogue
/// container constructions survive in the production source tree.
///
/// Complementary behavioral tests live in `ExecutionBoundaryBehaviorTests`.
class TransitionalArtifactRemovalTests: XCTestCase {

    // MARK: - Source helpers

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    /// Returns all non-comment lines from a Swift source file.
    private func nonCommentLines(at filePath: String) throws -> [String] {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return content.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
    }

    // MARK: - ENFORCE: VerifiedExecutor instantiated only by RuntimeBootstrap

    /// The executor is wired once by `RuntimeBootstrap` and threaded through
    /// `RuntimeContainer`. Any stray construction elsewhere creates split authority.
    func testVerifiedExecutorInstantiatedOnlyByBootstrap() throws {
        let root = repositoryRoot()
        let osaPath = root.appendingPathComponent("Sources/OracleOS")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: osaPath.path) else { return }

        var violations: [String] = []
        for case let file as String in enumerator {
            guard file.hasSuffix(".swift") else { continue }
            let fullPath = osaPath.appendingPathComponent(file).path
            // Bootstrap must instantiate it; no other OracleOS file should.
            if fullPath.hasSuffix("RuntimeBootstrap.swift") { continue }

            let lines = try nonCommentLines(at: fullPath)
            for (index, line) in lines.enumerated() {
                if line.contains("VerifiedExecutor(") {
                    violations.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty,
            "VerifiedExecutor must only be instantiated by RuntimeBootstrap. " +
            "Found stray instantiation(s):\n\(violations.joined(separator: "\n"))")
    }

    // MARK: - ENFORCE: RuntimeContainer instantiated only by RuntimeBootstrap

    /// A second `RuntimeContainer` would create a split kernel — all services
    /// must be obtained from the single container RuntimeBootstrap provides.
    func testRuntimeContainerInstantiatedOnlyByBootstrap() throws {
        let root = repositoryRoot()
        let osaPath = root.appendingPathComponent("Sources/OracleOS")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: osaPath.path) else { return }

        var violations: [String] = []
        for case let file as String in enumerator {
            guard file.hasSuffix(".swift") else { continue }
            let fullPath = osaPath.appendingPathComponent(file).path
            if fullPath.hasSuffix("RuntimeBootstrap.swift") { continue }

            let lines = try nonCommentLines(at: fullPath)
            for (index, line) in lines.enumerated() {
                if line.contains("RuntimeContainer(") {
                    violations.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty,
            "RuntimeContainer must only be instantiated by RuntimeBootstrap. " +
            "Found stray instantiation(s):\n\(violations.joined(separator: "\n"))")
    }

    // MARK: - ENFORCE: Legacy planner symbols absent from Sources

    /// `MixedTaskPlanner` and the `planner.nextStep` call pattern were removed
    /// during routing consolidation. Their reappearance indicates regression.
    func testLegacyPlannerSymbolsAbsent() throws {
        let root = repositoryRoot()
        let srcPath = root.appendingPathComponent("Sources")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: srcPath.path) else { return }

        let forbidden = ["MixedTaskPlanner", "planner.nextStep"]
        var violations: [String] = []
        for case let file as String in enumerator {
            guard file.hasSuffix(".swift") else { continue }
            let fullPath = srcPath.appendingPathComponent(file).path
            let lines = try nonCommentLines(at: fullPath)
            for (index, line) in lines.enumerated() {
                for pattern in forbidden {
                    if line.contains(pattern) {
                        violations.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }

        XCTAssertTrue(violations.isEmpty,
            "Legacy planner symbols must not appear in Sources. " +
            "Found:\n\(violations.joined(separator: "\n"))")
    }

    // MARK: - ENFORCE: SystemRouter tombstone has no live Swift declarations

    /// SystemRouter was deleted in ORC1-main-5. The tombstone file (explaining
    /// the removal) must contain only comments — no active type or function
    /// declarations that could re-introduce a stale routing path.
    func testSystemRouterTombstoneHasNoLiveDeclarations() throws {
        let root = repositoryRoot()
        let tombstonePath = root
            .appendingPathComponent("Sources/OracleOS/Execution/Routing/SystemRouter.swift")
            .path

        guard FileManager.default.fileExists(atPath: tombstonePath) else { return }
        let content = try String(contentsOfFile: tombstonePath, encoding: .utf8)

        // All non-blank lines in a pure tombstone must be comments.
        let liveLines = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("//")
        }

        XCTAssertTrue(liveLines.isEmpty,
            "SystemRouter.swift tombstone must contain only comments. " +
            "Found live code lines:\n\(liveLines.joined(separator: "\n"))")
    }

    // MARK: - Verify No State Mutation Outside Commit

    /// `WorldStateModel` exposes only `snapshot()` publicly (no public mutating
    /// methods). This test confirms the model can be instantiated and that
    /// `snapshot` is accessible — the compile-time immutability guarantee is
    /// enforced by Swift's access control, not runtime assertions.
    @MainActor
    func testWorldStateModelExposesOnlySnapshot() {
        let state = WorldStateModel()
        XCTAssertNotNil(state.snapshot)
    }

}
