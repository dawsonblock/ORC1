import Foundation
import XCTest
@testable import OracleOS

/// Governance tests that enforce architectural boundaries through source scans
/// and static structural proofs. Runtime behavior proofs live in
/// ExecutionBoundaryBehaviorTests.
final class ExecutionBoundaryEnforcementTests: XCTestCase {

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while true {
            if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url
            }
            url = parent
        }
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Real Enforcement: Source Code Scans

    /// ENFORCE: RuntimeContext must not expose execution-adjacent services
    func testRuntimeContextForbidsExecutionAdjacentServices() throws {
        let sourcePath = "Sources/OracleOS/Runtime/RuntimeContext.swift"
        let content = try String(contentsOfFile: sourcePath, encoding: .utf8)
        
        // These properties were removed and guarded against re-introduction
        XCTAssertFalse(content.contains("public let policyEngine:"),
                       "policyEngine is execution-adjacent and FORBIDDEN on RuntimeContext")
        XCTAssertFalse(content.contains("public let workspaceRunner:"),
                       "workspaceRunner is execution-adjacent and FORBIDDEN on RuntimeContext")
        XCTAssertFalse(content.contains("public let repositoryIndexer:"),
                       "repositoryIndexer is execution-adjacent and FORBIDDEN on RuntimeContext")
        
        // Verify compile-time guards are in place
        XCTAssertTrue(content.contains("@available(*, unavailable"),
                      "Compile-time guards must prevent re-introduction")
    }

    /// ENFORCE: UIRouter must NOT reference AutomationHost as an execution authority.
    /// UIRouter dispatches to Actions.perform* directly. AutomationHost is an
    /// observation/snapshot tool only; it must never appear in UIRouter's non-comment code.
    func testUIRouterDoesNotInvokeAutomationHost() throws {
        let sourcePath = "Sources/OracleOS/Execution/Routing/UIRouter.swift"
        let content = try String(contentsOfFile: sourcePath, encoding: .utf8)

        // Strip comment lines before scanning, so documentary mentions don't trip the check.
        let nonCommentLines = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.hasPrefix("//") && !trimmed.hasPrefix("*") && !trimmed.hasPrefix("/*")
        }
        let nonCommentSource = nonCommentLines.joined(separator: "\n")

        XCTAssertFalse(nonCommentSource.contains("automationHost"),
                       "UIRouter must not reference automationHost — it is an observation tool, not execution authority")
        XCTAssertFalse(nonCommentSource.contains("AutomationHost("),
                       "UIRouter must not construct AutomationHost — execution routes through Actions.perform*")
    }

    /// ENFORCE: Only approved files may create Process()
    func testProcessCreationOnlyInApprovedFiles() throws {
        let sourcePath = "Sources"
        let allowedFiles = Set([
            "DefaultProcessAdapter.swift",
            "DefaultProcessAdapter+Daemon.swift",
        ])
        
        let forbiddenDirectories = [
            "Sources/OracleOS/Runtime",
            "Sources/OracleOS/Planning",
            "Sources/OracleOS/State",
            "Sources/OracleOS/Events",
            "Sources/OracleOS/Core",
            "Sources/OracleOS/Memory",
        ]
        
        let fileManager = FileManager.default
        for forbiddenDir in forbiddenDirectories {
            guard let enumerator = fileManager.enumerator(atPath: forbiddenDir) else { continue }
            
            for case let file as String in enumerator {
                guard file.hasSuffix(".swift") else { continue }
                let filePath = (forbiddenDir as NSString).appendingPathComponent(file)
                
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                for (index, line) in lines.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Skip comments
                    if trimmed.hasPrefix("//") { continue }
                    
                    if line.contains("Process()") || line.contains("Foundation.Process()") {
                        XCTFail("Found Process() in forbidden location: \(filePath):\(index + 1)")
                    }
                }
            }
        }
    }

    /// ENFORCE: Direct runtime bootstrap ownership stays explicit.
    func testDirectBootstrapOwnersStayExplicit() throws {
        let directBootstrapOwners = [
            "Sources/OracleControllerHost/ControllerRuntimeBridge.swift",
            "Sources/OracleOS/MCP/MCPRuntimeHost.swift",
        ]

        for ownerPath in directBootstrapOwners {
            guard FileManager.default.fileExists(atPath: ownerPath) else { continue }
            let content = try String(contentsOfFile: ownerPath, encoding: .utf8)

            XCTAssertTrue(content.contains("RuntimeBootstrap") || content.contains("makeBootstrappedRuntime"),
                          "\(ownerPath) must use RuntimeBootstrap for entry")
        }

        let dispatchPath = "Sources/OracleOS/MCP/MCPDispatch.swift"
        let dispatchContent = try String(contentsOfFile: dispatchPath, encoding: .utf8)

        XCTAssertTrue(dispatchContent.contains("MCPRuntimeHost"),
                      "MCPDispatch must delegate runtime lifecycle ownership to MCPRuntimeHost")
        XCTAssertFalse(dispatchContent.contains("_bootstrappedRuntime"),
                       "MCPDispatch must not reintroduce an ad hoc cached runtime")
    }

    /// ENFORCE: ControllerRuntimeBridge does not store RuntimeContext
    func testControllerBridgeDoesNotStoreContext() throws {
        let bridgePath = "Sources/OracleControllerHost/ControllerRuntimeBridge.swift"
        let content = try String(contentsOfFile: bridgePath, encoding: .utf8)
        
        XCTAssertFalse(content.contains("let runtimeContext: RuntimeContext"),
                       "Bridge must not store RuntimeContext as first-class object")
        XCTAssertTrue(content.contains("private let bootstrappedRuntime: BootstrappedRuntime"),
                      "Bridge must store BootstrappedRuntime instead")
    }

    /// ENFORCE: CommandPayload enum is exhaustively handled
    func testCommandPayloadExhaustiveness() {
        let payload: CommandPayload = .build(BuildSpec(workspaceRoot: "/tmp"))
        
        // This switch must handle ALL cases. Adding a new case will fail this test.
        switch payload {
        case .build(_): break
        case .test(_): break
        case .git(_): break
        case .file(_): break
        case .ui(_): break
        case .code(_): break
        }
    }

    /// ENFORCE: Governance tests themselves check for violations
    func testGovernanceTestsCheckForbiddenPatterns() throws {
        let governanceTestPath = "Tests/OracleOSTests/Governance/ArchitectureFreezeTests.swift"
        guard FileManager.default.fileExists(atPath: governanceTestPath) else {
            XCTFail("Architecture freeze tests must exist")
            return
        }
        
        let content = try String(contentsOfFile: governanceTestPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Process()"),
                      "Governance tests must check for forbidden Process() usage")
    }

    /// ENFORCE: The execution boundary guard must bless exact write owners, not namespaces.
    func testExecutionBoundaryGuardUsesExplicitWriteAuthorities() throws {
        let content = try readRepositoryFile("scripts/execution_boundary_guard.py")

        XCTAssertTrue(content.contains("ALLOWED_WRITE_AUTHORITIES = {"),
                      "Write authority must be expressed as an explicit file map")
        XCTAssertFalse(content.contains("ALLOWED_WRITE_DIRS = ["),
                       "Broad write-directory allowlists must not be reintroduced")

        let requiredAuthorities = [
            "Sources/OracleOS/Code/Execution/WorkspaceRunner.swift",
            "Sources/OracleOS/Execution/Experiments/ExperimentManager.swift",
            "Sources/OracleOS/Execution/Experiments/WorktreeSandbox.swift",
            "Sources/OracleOS/Events/FileEventStore.swift",
            "Sources/OracleOS/Events/Commit/CommitWAL.swift",
            "Sources/OracleOS/Intent/Policies/ApprovalStore.swift",
            "Sources/OracleOS/WorldModel/Graph/GraphPersistence.swift",
        ]

        for authority in requiredAuthorities {
            XCTAssertTrue(content.contains("\"\(authority)\""),
                          "Guard must explicitly account for write authority: \(authority)")
        }

        XCTAssertTrue(content.contains("FileManager.createDirectory"),
                      "Guard must scan for directory creation writes")
        XCTAssertTrue(content.contains("FileHandle(forWritingTo:)"),
                      "Guard must scan for file-handle based appends")
        XCTAssertTrue(content.contains("sqlite3_open"),
                      "Guard must scan for SQLite-backed persistence")
    }

    /// ENFORCE: The checked-in execution boundary guard must pass on the current repo.
    func testExecutionBoundaryGuardPassesCurrentRepository() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "scripts/execution_boundary_guard.py"]
        process.currentDirectoryURL = repositoryRoot()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let combined = String(decoding: stdoutData + stderrData, as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0, "execution_boundary_guard.py failed:\n\(combined)")
    }

    // MARK: - Meta-test: Governance test presence

    /// ENFORCE: Test files that verify boundaries must exist
    func testGovernanceTestsExist() {
        let requiredTests = [
            "Tests/OracleOSTests/Governance/ExecutionBoundaryEnforcementTests.swift",
            "Tests/OracleOSTests/Governance/ExecutionBoundaryBehaviorTests.swift",
            "Tests/OracleOSTests/Governance/ArchitectureFreezeTests.swift",
            "Tests/OracleOSTests/Governance/RuntimeInvariantTests.swift",
        ]
        
        for testFile in requiredTests {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: testFile),
                "Required governance test missing: \(testFile)"
            )
        }
    }
}
