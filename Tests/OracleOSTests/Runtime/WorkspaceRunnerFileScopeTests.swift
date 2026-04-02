import Foundation
import Testing
@testable import OracleOS

@Suite("WorkspaceRunner File Scope Policy")
struct WorkspaceRunnerFileScopeTests {
    
    // A stub adapter to satisfy init
    final class MockAdapter: ProcessAdapter, @unchecked Sendable {
        func run(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy?) async throws -> ProcessResult {
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        func runSync(_ command: SystemCommand, in workspace: WorkspaceContext?, policy: CommandExecutionPolicy?) throws -> ProcessResult {
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        func spawnBackground(_ command: SystemCommand, in workspace: WorkspaceContext?) throws -> any BackgroundProcess {
            struct DummyBackground: BackgroundProcess {
                var processIdentifier: Int32 = 0
                func terminate() {}
            }
            return DummyBackground()
        }
    }

    @Test("Rejects attempting to break out of workspace with ../")
    func rejectsParentTraversal() async throws {
        let runner = WorkspaceRunner(processAdapter: MockAdapter())
        let spec = FileMutationSpec(
            path: "../../etc/passwd",
            operation: .write,
            content: "test",
            workspaceRoot: "/tmp/workspace"
        )
        
        await #expect(throws: WorkspaceRunnerError.self) {
            try await runner.applyFile(spec)
        }
    }
    
    @Test("Rejects attempting to write to absolute /tmp/file outside workspace")
    func rejectsAbsoluteOutside() async throws {
        let runner = WorkspaceRunner(processAdapter: MockAdapter())
        let spec = FileMutationSpec(
            path: "/tmp/file",
            operation: .write,
            content: "test",
            workspaceRoot: "/Users/test/workspace"
        )
        
        await #expect(throws: WorkspaceRunnerError.self) {
            try await runner.applyFile(spec)
        }
    }
    
    @Test("Allows and resolves valid in-repo path")
    func allowsValidInRepoPath() async throws {
        let runner = WorkspaceRunner(processAdapter: MockAdapter())
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: workspace, withIntermediateDirectories: true, attributes: nil)
        
        let spec = FileMutationSpec(
            path: "test.txt",
            operation: .write,
            content: "hello",
            workspaceRoot: workspace
        )
        
        try await runner.applyFile(spec)
        
        let content = try String(contentsOfFile: workspace + "/test.txt")
        #expect(content == "hello")
    }
}
