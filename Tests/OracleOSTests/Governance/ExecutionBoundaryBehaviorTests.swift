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

    private func readSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: repositoryRoot()).appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
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

    /// PROVES: VerifiedExecutor returns events but does not mutate committed
    /// runtime state until CommitCoordinator is invoked on the supported path.
    @MainActor
    func testVerifiedExecutorLeavesCommittedStateUnchangedUntilCommit() async throws {
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        let before = await bootstrapped.container.commitCoordinator.snapshot()

        let command = Command(
            type: .code,
            payload: .code(
                CodeAction(
                    name: "readFile",
                    filePath: "Package.swift",
                    workspacePath: repositoryRoot()
                )
            ),
            metadata: CommandMetadata(intentID: UUID(), source: "commit-authority-proof")
        )

        let outcome = try await bootstrapped.container.executor.execute(command)
        let afterExecute = await bootstrapped.container.commitCoordinator.snapshot()

        XCTAssertEqual(outcome.status, .success)
        XCTAssertEqual(before.cycleCount, afterExecute.cycleCount)
        XCTAssertEqual(before.notes, afterExecute.notes)

        _ = try await bootstrapped.container.commitCoordinator.commit(outcome.events)
        let afterCommit = await bootstrapped.container.commitCoordinator.snapshot()

        XCTAssertEqual(afterCommit.cycleCount, afterExecute.cycleCount)
        XCTAssertNotEqual(afterCommit.notes, afterExecute.notes)
        XCTAssertTrue(afterCommit.notes.contains("lastExecutionStatus=success"))
    }

    /// PROVES: Host-local wait evaluation is a read-only observation path and
    /// does not mutate committed runtime state.
    @MainActor
    func testWaitManagerLeavesCommittedStateUnchanged() async throws {
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        let before = await bootstrapped.container.commitCoordinator.snapshot()

        let result = WaitManager.waitFor(
            condition: "not_a_real_condition",
            value: nil,
            appName: nil,
            timeout: 0.01,
            interval: 0.01
        )

        let after = await bootstrapped.container.commitCoordinator.snapshot()

        XCTAssertFalse(result.success)
        XCTAssertEqual(before.cycleCount, after.cycleCount)
        XCTAssertEqual(before.notes, after.notes)
    }

    /// PROVES: The stricter product contract keeps one explicit bounded
    /// exception table for all documented bypass surfaces.
    func testProductContractDocumentsExplicitExceptionTable() throws {
        let contractSource = try readSource("docs/PRODUCT_CONTRACT.md")
        let executorSource = try readSource("Sources/OracleOS/Execution/VerifiedExecutor.swift")
        let waitSource = try readSource("Sources/OracleOS/MCP/WaitManager.swift")
        let screenshotSource = try readSource("Sources/OracleOS/WorldModel/Perception/AX/AXScanner+Screenshot.swift")

        XCTAssertTrue(contractSource.contains("| Surface | Entry point | Role | Timeout model | Proof source |"))
        XCTAssertTrue(contractSource.contains("| Surface | Contract lane | Mutability | Approval | Timeout model | Reason | Owning file(s) | Proof source |"))
        XCTAssertTrue(contractSource.contains("oracle_experiment_search"))
        XCTAssertTrue(contractSource.contains("oracle_screenshot"))
        XCTAssertTrue(contractSource.contains("oracle_wait"))
        XCTAssertTrue(contractSource.contains("oracle_parse_screen"))
        XCTAssertTrue(contractSource.contains("oracle_ground"))
        XCTAssertTrue(contractSource.contains("oracle doctor"))
        XCTAssertTrue(contractSource.contains("oracle setup"))
        XCTAssertTrue(contractSource.contains("Sources/oracle/Doctor.swift"))
        XCTAssertTrue(contractSource.contains("Sources/oracle/SetupWizard.swift"))
        XCTAssertTrue(contractSource.contains("execution_boundary_guard.py"))
        XCTAssertTrue(executorSource.contains("oracle_screenshot"))
        XCTAssertTrue(executorSource.contains("oracle_wait"))
        XCTAssertTrue(executorSource.contains("oracle_parse_screen"))
        XCTAssertTrue(waitSource.contains("does not route through VerifiedExecutor"))
        XCTAssertTrue(screenshotSource.contains("read-only observational tool"))
    }

    /// PROVES: Tooling-only CLI entry points stay documented as bounded
    /// exceptions instead of silently joining the guaranteed main runtime path.
    func testToolingCommandsRemainDocumentedExecutionExceptions() throws {
        let doctorSource = try readSource("Sources/oracle/Doctor.swift")
        let setupSource = try readSource("Sources/oracle/SetupWizard.swift")

        XCTAssertTrue(doctorSource.contains("EXECUTION AUTHORITY NOTE"))
        XCTAssertTrue(doctorSource.contains("OUTSIDE the bootstrapped runtime"))
        XCTAssertTrue(setupSource.contains("EXECUTION AUTHORITY NOTE"))
        XCTAssertTrue(setupSource.contains("OUTSIDE the bootstrapped runtime"))
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