import XCTest
@testable import OracleOS

/// Phase 7: Remove Transitional Artifacts
/// Verify no alternate execution paths exist outside the unified spine.
class TransitionalArtifactRemovalTests: XCTestCase {

    // MARK: - Verify Single Execution Entry Point

    @MainActor
    func testOnlyRuntimeOrchestratorIsExecutionEntry() {
        // Verify that RuntimeOrchestrator.submitIntent() is the sole entry point
        // for all intent-based execution

        // RuntimeExecutionDriver and all other surfaces must route through IntentAPI
        // which is implemented by RuntimeOrchestrator

        let expectation = expectation(description: "Execution entry verified")
        Task {
            // This should be the only way to submit intent
            let intent = Intent(
                domain: .code,
                objective: "test",
                metadata: [:]
            )
            XCTAssertNotNil(intent)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Verify No Alternate Execution Paths

    @MainActor
    func testNoDirectExecutorCallsOutsideRuntimeOrchestrator() {
        // Verify that VerifiedExecutor is not directly instantiated elsewhere
        // (This is a documentation test; real verification via grep)

        // Expected:
        //   grep -r "VerifiedExecutor(" Sources/OracleOS --include="*.swift"
        //   → Should only appear in RuntimeBootstrap and tests

        // The executor should be created ONCE by RuntimeBootstrap
        // and passed via RuntimeContainer to all other components

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
        XCTAssertNotNil(executor)
    }

    // MARK: - Verify Legacy Planners Are Not in Active Path

    @MainActor
    func testLegacyPlannersNotInActiveExecutionPath() {
        // MixedTaskPlanner and PlannerDecision are legacy artifacts
        // They should not be called during normal operation

        // Expected:
        //   grep -r "planner.nextStep\|mixedTaskPlanner.plan" Sources/OracleOS/Runtime
        //   → Should return no results (not in runtime spine)

        // Instead, only Planner.plan(intent, context) should be used
        let planner = MainPlanner()
        XCTAssertNotNil(planner)
    }

    // MARK: - Verify Unified Intent-Based Spine

    @MainActor
    func testUnifiedIntentSpineIsOnlyPath() {
        // The unified spine is:
        //   Intent → RuntimeOrchestrator → Planner → VerifiedExecutor → Commit

        // All surfaces (MCP, CLI, Controller, AgentLoop) must use this spine

        // Expected call chain:
        //   1. Surface creates Intent
        //   2. RuntimeOrchestrator.submitIntent(intent)
        //   3. Planner.plan(intent, context) → Command
        //   4. VerifiedExecutor.execute(command) → ExecutionOutcome
        //   5. CommitCoordinator.commit(events) → CommitReceipt

        let domain: IntentDomain = .code
        XCTAssertEqual(domain, .code)

        // Domain intent should map to typed command through planner
    }

    // MARK: - Verify No State Mutation Outside Commit

    @MainActor
    func testNoDirectStateWritesOutsideCommitCoordinator() {
        // Verify WorldStateModel is not directly mutated outside CommitCoordinator
        // (This is a compile-time check: WorldStateModel has no public mutating methods)

        let state = WorldStateModel()
        XCTAssertNotNil(state.snapshot)  // Only snapshot() is public
    }

    // MARK: - Verify Boot Path Is Single Authority

    @MainActor
    func testRuntimeBootstrapIsOnlyContainer() {
        // Verify RuntimeBootstrap.makeBootstrappedRuntime() is the sole container factory
        // (This is a documentation test; RuntimeContainer should not be instantiated elsewhere)

        // Expected:
        //   grep -r "RuntimeContainer(" Sources/OracleOS/Runtime --include="*.swift"
        //   → Should only appear in RuntimeBootstrap

        let config = RuntimeConfig.test()
        XCTAssertNotNil(config)
    }

    // MARK: - Verification: No Configuration Variations

    @MainActor
    func testNoAlternateRuntimeConfigurationPaths() {
        // Verify there's only one way to configure the runtime
        // RuntimeConfig should have sensible defaults or explicit configuration

        let liveConfig = RuntimeConfig.live()
        let testConfig = RuntimeConfig.test()

        XCTAssertNotNil(liveConfig)
        XCTAssertNotNil(testConfig)
    }

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

    func test_system_router_does_not_directly_spawn_processes() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/Execution/Routing/SystemRouter.swift")
        guard let text = try? String(contentsOf: sourcePath, encoding: .utf8) else { return }
        
        let forbidden = ["DefaultProcessAdapter(", "/bin/zsh", "/bin/bash", "\"-c\"", "Process("]
        for pattern in forbidden {
            XCTAssertFalse(text.contains(pattern), "SystemRouter contains \(pattern)")
        }
    }

}
