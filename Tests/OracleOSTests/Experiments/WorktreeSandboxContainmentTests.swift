import Testing
import Foundation
@testable import OracleOS

@Suite("WorktreeSandbox Containment")
struct WorktreeSandboxContainmentTests {

    // MARK: - Helpers

    /// Creates a minimal WorktreeSandbox backed by a real temp directory so we
    /// can drive apply() without a live git worktree for the path-validation tests.
    private func makeSandbox(root: URL) -> WorktreeSandbox {
        WorktreeSandbox(
            experimentID: "test-exp",
            candidateID: "test-cand",
            workspaceRoot: root.path,
            sandboxPath: root.path,
            branchName: "codex/exp-test"
        )
    }

    private func makePatch(path: String) -> CandidatePatch {
        CandidatePatch(
            id: "p1",
            title: "Test patch",
            summary: "containment test",
            workspaceRelativePath: path,
            content: "// test"
        )
    }

    // MARK: - Boundary enforcement (no real FS needed — guard fires before file ops)

    @Test("Absolute path is rejected before canonicalization")
    func absolutePathRejected() throws {
        let sandbox = makeSandbox(root: URL(fileURLWithPath: "/tmp/oracle-sandbox-test"))
        let patch = makePatch(path: "/etc/passwd")
        #expect(throws: SandboxError.self) {
            try sandbox.apply(patch)
        }
    }

    @Test("Traversal sequence is rejected before canonicalization")
    func traversalSequenceRejected() throws {
        let sandbox = makeSandbox(root: URL(fileURLWithPath: "/tmp/oracle-sandbox-test"))
        let patch = makePatch(path: "../../etc/passwd")
        #expect(throws: SandboxError.self) {
            try sandbox.apply(patch)
        }
    }

    @Test("Absolute path throw is specifically invalidRelativePath")
    func absolutePathThrowsCorrectCase() throws {
        let sandbox = makeSandbox(root: URL(fileURLWithPath: "/tmp/oracle-sandbox-test"))
        let patch = makePatch(path: "/etc/passwd")
        do {
            try sandbox.apply(patch)
            Issue.record("Expected SandboxError.invalidRelativePath to be thrown")
        } catch let error as SandboxError {
            guard case .invalidRelativePath = error else {
                Issue.record("Wrong SandboxError case: \(error)")
                return
            }
        }
    }

    @Test("Traversal sequence throw is specifically invalidRelativePath")
    func traversalThrowsCorrectCase() throws {
        let sandbox = makeSandbox(root: URL(fileURLWithPath: "/tmp/oracle-sandbox-test"))
        let patch = makePatch(path: "../sibling/secret.swift")
        do {
            try sandbox.apply(patch)
            Issue.record("Expected SandboxError.invalidRelativePath to be thrown")
        } catch let error as SandboxError {
            guard case .invalidRelativePath = error else {
                Issue.record("Wrong SandboxError case: \(error)")
                return
            }
        }
    }

    @Test("Rejected traversal leaves outside file untouched")
    func rejectedTraversalDoesNotMutateOutsideSandbox() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oracle-sandbox-boundary-\(UUID().uuidString)", isDirectory: true)
        let sandboxRoot = tmpDir.appendingPathComponent("sandbox", isDirectory: true)
        let outsideFile = tmpDir.appendingPathComponent("outside.txt")
        try FileManager.default.createDirectory(at: sandboxRoot, withIntermediateDirectories: true)
        try "original".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sandbox = makeSandbox(root: sandboxRoot)
        let patch = makePatch(path: "../outside.txt")

        #expect(throws: SandboxError.self) {
            try sandbox.apply(patch)
        }

        let outsideContents = try String(contentsOf: outsideFile, encoding: .utf8)
        #expect(outsideContents == "original")
    }

    // MARK: - Happy path (real temp directory)

    @Test("Valid relative path writes file inside sandbox")
    func validRelativePathSucceeds() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oracle-sandbox-containment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sandbox = makeSandbox(root: tmpDir)
        let patch = makePatch(path: "Sources/Foo.swift")
        try sandbox.apply(patch)

        let expected = tmpDir.appendingPathComponent("Sources/Foo.swift")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        let content = try String(contentsOf: expected, encoding: .utf8)
        #expect(content == "// test")
    }
}
