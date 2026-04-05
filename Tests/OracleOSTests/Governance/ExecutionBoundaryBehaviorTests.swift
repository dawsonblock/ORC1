import XCTest
@testable import OracleOS

/// Governance-adjacent behavior tests that prove important runtime boundaries by
/// executing real code paths instead of scanning source text.
final class ExecutionBoundaryBehaviorTests: XCTestCase {

    private func repositoryRoot() -> String {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default

        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url.path
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url.path
            }
            url = parent
        }
    }

    private func makeVerifiedExecutor(
        approvalsRoot: URL,
        stateProvider: (any WorldStateProviding)? = nil
    ) -> (executor: VerifiedExecutor, approvalStore: ApprovalStore) {
        let policyEngine = PolicyEngine(mode: .confirmRisky)
        let processAdapter = DefaultProcessAdapter(policyEngine: policyEngine)
        let commandRouter = CommandRouter(
            workspaceRunner: WorkspaceRunner(processAdapter: processAdapter),
            repositoryIndexer: RepositoryIndexer(processAdapter: processAdapter)
        )
        let approvalStore = ApprovalStore(rootDirectory: approvalsRoot)
        let executor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator(),
            stateProvider: stateProvider,
            approvalStore: approvalStore
        )
        return (executor, approvalStore)
    }

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

    /// PROVES: VerifiedExecutor creates, consumes, and invalidates approval receipts
    /// before a risky UI send action is allowed to execute.
    @MainActor
    func testVerifiedExecutorApprovalGateControlsRiskyUISendActions() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let approvalsRoot = tempRoot.appendingPathComponent("approvals", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let (executor, approvalStore) = makeVerifiedExecutor(approvalsRoot: approvalsRoot)
        let baseCommand = Command(
            type: .ui,
            payload: .ui(UIAction(name: "click", app: "Google Chrome", query: "Send")),
            metadata: CommandMetadata(intentID: UUID(), source: "controller.test")
        )

        let pending = try await executor.execute(baseCommand)
        XCTAssertEqual(pending.status, .approvalPending)

        guard let request = approvalStore.listPendingRequests().first else {
            XCTFail("Expected a pending approval request to be created")
            return
        }
        XCTAssertEqual(request.actionFingerprint, PolicyRules.commandFingerprint(baseCommand))

        _ = try approvalStore.approve(requestID: request.id)

        let approvedCommand = Command(
            id: baseCommand.id,
            type: baseCommand.type,
            payload: baseCommand.payload,
            metadata: CommandMetadata(
                intentID: baseCommand.metadata.intentID,
                source: baseCommand.metadata.source,
                approvalToken: request.id
            )
        )

        let approved = try await executor.execute(approvedCommand)
        XCTAssertEqual(approved.verifierReport.policyDecision, "approved")
        XCTAssertNotEqual(approved.status, .approvalPending)
        XCTAssertNotEqual(approved.status, .policyBlocked)

        let consumed = try await executor.execute(approvedCommand)
        XCTAssertEqual(consumed.status, .policyBlocked)
    }

    /// PROVES: Typed code commands can supply repository context directly even
    /// when the committed world snapshot has not yet observed a repository.
    @MainActor
    func testVerifiedExecutorAcceptsTypedWorkspaceRootForCodeReads() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let approvalsRoot = tempRoot.appendingPathComponent("approvals", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let provider = StaticWorldStateProvider(snapshot: WorldModelSnapshot())
        let (executor, _) = makeVerifiedExecutor(
            approvalsRoot: approvalsRoot,
            stateProvider: provider
        )

        let command = Command(
            type: .code,
            payload: .code(
                CodeAction(
                    name: "readFile",
                    filePath: "Package.swift",
                    workspacePath: repositoryRoot()
                )
            ),
            metadata: CommandMetadata(intentID: UUID(), source: "runtime-proof")
        )

        let result = try await executor.execute(command)
        XCTAssertEqual(result.status, .success)
        XCTAssertNotEqual(result.status, .preconditionFailed)
        XCTAssertNotEqual(result.status, .policyBlocked)
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

private struct StaticWorldStateProvider: WorldStateProviding {
    let snapshot: WorldModelSnapshot

    func snapshot() async -> WorldModelSnapshot {
        snapshot
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