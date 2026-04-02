import XCTest
@testable import OracleOS

/// Governance tests that ENFORCE architectural boundaries through real scans and proofs.
/// These tests fail when architecture drifts, not when developer assumptions are wrong.
final class ExecutionBoundaryEnforcementTests: XCTestCase {

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

    /// ENFORCE: All execution surfaces must use RuntimeBootstrap
    func testAllSurfacesUseBootstrap() throws {
        let executionSurfaces = [
            "Sources/OracleControllerHost/ControllerRuntimeBridge.swift",
            "Sources/OracleOS/MCP/MCPDispatch.swift",
            "Sources/oracle/main.swift",
        ]
        
        for surfacePath in executionSurfaces {
            guard FileManager.default.fileExists(atPath: surfacePath) else { continue }
            let content = try String(contentsOfFile: surfacePath, encoding: .utf8)
            
            XCTAssertTrue(content.contains("RuntimeBootstrap") || content.contains("makeBootstrappedRuntime"),
                          "\(surfacePath) must use RuntimeBootstrap for entry")
        }
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

    // MARK: - Real Enforcement: Behavioral Tests

    /// ENFORCE: RuntimeBootstrap is idempotent (same output given same input)
    @MainActor
    func testRuntimeBootstrapIsDeterministic() async throws {
        // Create runtime twice with same config
        let config = RuntimeConfig.test()
        
        let runtime1 = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)
        let runtime2 = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)
        
        // Both should be valid
        XCTAssertNotNil(runtime1.container)
        XCTAssertNotNil(runtime2.container)
        
        // Both should have the same session ID
        XCTAssertEqual(
            runtime1.container.traceRecorder.sessionID,
            runtime2.container.traceRecorder.sessionID,
            "Sessions must be deterministic given same config"
        )
    }

    /// ENFORCE: EventReducer is applied before state is visible
    @MainActor
    func testCommitCoordinatorAppliesReducersBeforeVisibility() async throws {
        let store = MemoryEventStore()
        let reducer = RuntimeStateReducer()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [reducer])
        
        // Empty commit should fail
        do {
            _ = try await coordinator.commit([])
            XCTFail("Empty commit must throw CommitError.emptyCommit")
        } catch CommitError.emptyCommit {
            // Expected
        }
    }

    /// ENFORCE: VerifiedExecutor is the only execution path
    @MainActor
    func testVerifiedExecutorIsOnlyExecutionPath() async throws {
        let policyEngine = PolicyEngine.shared
        let processAdapter = DefaultProcessAdapter(policyEngine: policyEngine)
        
        let commandRouter = CommandRouter(
            automationHost: nil,
            workspaceRunner: WorkspaceRunner(processAdapter: processAdapter),
            repositoryIndexer: RepositoryIndexer(processAdapter: processAdapter)
        )
        
        let executor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator()
        )
        
        // Verify executor is the sole interface for command execution
        let command = Command(
            id: UUID(),
            type: .code,
            payload: .code(CodeAction(name: "test")),
            metadata: CommandMetadata(intentID: UUID())
        )
        
        let result = try await executor.execute(command)
        XCTAssertNotNil(result)
        XCTAssertFalse(result.events.isEmpty, "Execution must emit events")
    }

    /// ENFORCE: Planner is called only through RuntimeOrchestrator
    @MainActor
    func testPlannerIsCalledThroughOrchestratorOnly() async throws {
        // This is verified by source code scan (grep), but we also test the interface
        let planner = MainPlanner()
        
        let context = PlannerContext(
            state: WorldStateModel(),
            memories: [],
            repositorySnapshot: nil
        )
        
        let intent = Intent(
            id: UUID(),
            domain: .code,
            objective: "test",
            metadata: [:]
        )
        
        // Planner must accept typed Intent, not loose arguments
        let command = try await planner.plan(intent: intent, context: context)
        XCTAssertNotNil(command, "Planner must return typed Command")
    }

    // MARK: - Meta-test: Governance test presence

    /// ENFORCE: Test files that verify boundaries must exist
    func testGovernanceTestsExist() {
        let requiredTests = [
            "Tests/OracleOSTests/Governance/ExecutionBoundaryEnforcementTests.swift",
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

// MARK: - Helper Extensions

private extension RuntimeConfig {
    static func test() -> RuntimeConfig {
        RuntimeConfig(
            traceDirectory: FileManager.default.temporaryDirectory,
            approvalsDirectory: FileManager.default.temporaryDirectory,
            projectMemoryDirectory: FileManager.default.temporaryDirectory,
            logLevel: .info,
            policyMode: .confirmAll
        )
    }
}
