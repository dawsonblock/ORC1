import XCTest
@testable import OracleOS

/// Governance-adjacent behavior tests that prove important runtime boundaries by
/// executing real code paths instead of scanning source text.
final class ExecutionBoundaryBehaviorTests: XCTestCase {

    /// PROVES: Bootstrap returns independently wired runtimes for the same config.
    @MainActor
    func testRuntimeBootstrapProducesIndependentStructuredRuntimes() async throws {
        let config = RuntimeConfig.test()

        let runtime1 = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)
        let runtime2 = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)

        XCTAssertNotNil(runtime1.container)
        XCTAssertNotNil(runtime1.orchestrator)
        XCTAssertNotNil(runtime2.container)
        XCTAssertNotNil(runtime2.orchestrator)
        XCTAssertFalse(runtime1.container === runtime2.container,
                       "Separate bootstrap calls must return separate runtime containers")
    }

    /// PROVES: CommitCoordinator rejects empty commits rather than mutating state implicitly.
    @MainActor
    func testCommitCoordinatorRejectsEmptyCommit() async throws {
        let store = MemoryEventStore()
        let reducer = RuntimeStateReducer()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [reducer])

        do {
            _ = try await coordinator.commit([])
            XCTFail("Empty commit must throw CommitError.emptyCommit")
        } catch CommitError.emptyCommit {
            // Expected
        }
    }

    /// PROVES: VerifiedExecutor accepts typed commands and emits events.
    @MainActor
    func testVerifiedExecutorExecutesTypedCommandAndEmitsEvents() async throws {
        let policyEngine = PolicyEngine.shared
        let processAdapter = DefaultProcessAdapter(policyEngine: policyEngine)

        let commandRouter = CommandRouter(
            workspaceRunner: WorkspaceRunner(processAdapter: processAdapter),
            repositoryIndexer: RepositoryIndexer(processAdapter: processAdapter)
        )

        let executor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator()
        )

        let command = Command(
            id: UUID(),
            type: .code,
            payload: .code(CodeAction(name: "test")),
            metadata: CommandMetadata(intentID: UUID(), source: "test")
        )

        let result = try await executor.execute(command)
        XCTAssertFalse(result.events.isEmpty, "Execution must emit events")
    }

    /// PROVES: Planner interface is typed (`Intent` -> `Command`) even outside runtime wiring.
    @MainActor
    func testPlannerAcceptsTypedIntentAndReturnsTypedCommand() async throws {
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

        let command = try await planner.plan(intent: intent, context: context)
        XCTAssertNotNil(command, "Planner must return typed Command")
    }

    /// PROVES: RuntimeContext is a minimal guard object with no stored runtime authority.
    @MainActor
    func testRuntimeContextHasNoStoredRuntimeAuthority() {
        let context = RuntimeContext()
        let mirror = Mirror(reflecting: context)

        XCTAssertTrue(mirror.children.isEmpty,
                      "RuntimeContext must remain empty at runtime; authority lives in RuntimeContainer")
    }
}

private extension RuntimeConfig {
    static func test() -> RuntimeConfig {
        let tmp = FileManager.default.temporaryDirectory
        return RuntimeConfig(
            policyMode: .confirmRisky,
            approvalRequiredSurfaces: [],
            blockedApplications: [],
            protectedOperations: [],
            traceDirectory: tmp,
            recipesDirectory: tmp,
            controllerApprovalRequiredForRiskyActions: false,
            approvalsDirectory: tmp,
            projectMemoryDirectory: tmp,
            experimentsDirectory: tmp
        )
    }
}