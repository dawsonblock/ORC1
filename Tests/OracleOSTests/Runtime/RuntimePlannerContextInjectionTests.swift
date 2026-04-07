import Foundation
import XCTest
@testable import OracleOS

@MainActor
final class RuntimePlannerContextInjectionTests: XCTestCase {

    private actor PlannerSpy: Planner {
        private var lastContext: PlannerContext?

        func plan(intent: Intent, context: PlannerContext) async throws -> Command {
            lastContext = context
            return Command(
                type: .code,
                payload: .code(
                    CodeAction(
                        name: "searchRepository",
                        query: intent.objective,
                        workspacePath: context.repositorySnapshot?.workspaceRoot ?? intent.workspaceRoot
                    )
                ),
                metadata: CommandMetadata(intentID: intent.id, source: "test.spy")
            )
        }

        func lastPlannedContext() -> PlannerContext? {
            lastContext
        }
    }

    func testRepositorySnapshotInjectionFromWorkspaceMetadata() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let runtime = try await makeSpyRuntime()
        let intent = Intent(
            domain: .code,
            objective: "search calculator implementation",
            metadata: ["workspacePath": workspace.path]
        )

        _ = try await runtime.orchestrator.submitIntent(intent)
        let context = await runtime.planner.lastPlannedContext()

        XCTAssertEqual(context?.repositorySnapshot?.workspaceRoot, workspace.path)
    }

    func testMemoryInjectionIsBoundedAndWorkspaceScoped() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let runtime = try await makeSpyRuntime()
        runtime.container.memoryStore.setWorkspaceRoot(workspace.path)
        try runtime.container.memoryStore.recordKnownGoodPattern(
            title: "Known good calculator fix",
            summary: "Prefer Sources/Example/Calculator.swift for calculator repairs.",
            knowledgeClass: .reusable,
            affectedModules: ["Sources/Example"],
            body: "Restore Sources/Example/Calculator.swift before touching tests."
        )

        let intent = Intent(
            domain: .code,
            objective: "fix Sources/Example/Calculator.swift",
            metadata: ["workspacePath": workspace.path]
        )

        _ = try await runtime.orchestrator.submitIntent(intent)
        let context = await runtime.planner.lastPlannedContext()
        let memories = context?.memories ?? []

        XCTAssertFalse(memories.isEmpty)
        XCTAssertLessThanOrEqual(memories.count, 5)
        XCTAssertTrue(
            memories.contains(where: { $0.source.contains(".oracle") || $0.source.contains("ProjectMemory") }),
            "Expected workspace-scoped project memory sources"
        )
    }

    func testMainPlannerEditFailsClosedWithoutWorkspaceRoot() async throws {
        let planner = MainPlanner()
        let intent = Intent(
            domain: .code,
            objective: "edit calculator implementation",
            metadata: [
                "filePath": "Sources/Example/Calculator.swift",
                "patch": "public struct Calculator {}"
            ]
        )

        let command = try await planner.plan(intent: intent, context: PlannerContext(state: WorldStateModel()))

        switch command.payload {
        case .code(let action):
            XCTAssertEqual(action.name, "readFile")
            XCTAssertEqual(action.filePath, "Sources/Example/Calculator.swift")
        case .file:
            XCTFail("Edit without workspace context must fail closed to a read-only command")
        default:
            XCTFail("Expected a read-only code action after edit demotion")
        }

        XCTAssertTrue(command.metadata.traceTags.contains("fail-closed"))
        XCTAssertTrue(command.metadata.traceTags.contains("missing-workspace-root"))
        XCTAssertTrue(command.metadata.traceTags.contains("edit-demoted-to-read"))
    }

    func testWorkspaceResolutionFallsBackToCommittedState() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let runtime = try await makeSpyRuntime(
            initialSnapshot: WorldModelSnapshot(repositoryRoot: workspace.path)
        )
        let intent = Intent(
            domain: .code,
            objective: "search calculator implementation"
        )

        _ = try await runtime.orchestrator.submitIntent(intent)
        let context = await runtime.planner.lastPlannedContext()

        XCTAssertEqual(context?.repositorySnapshot?.workspaceRoot, workspace.path)
    }

    private func makeSpyRuntime(
        initialSnapshot: WorldModelSnapshot = WorldModelSnapshot()
    ) async throws -> (orchestrator: RuntimeOrchestrator, planner: PlannerSpy, container: RuntimeContainer) {
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        let planner = PlannerSpy()
        let reducer = CompositeStateReducer(reducers: [
            MemoryStateReducer(),
            UIStateReducer(),
            RuntimeStateReducer(),
            ProjectStateReducer(),
        ])
        let eventStore = MemoryEventStore()
        let commitCoordinator = CommitCoordinator(
            eventStore: eventStore,
            reducers: [reducer],
            initialState: WorldStateModel(snapshot: initialSnapshot)
        )
        let stateProvider = RuntimeWorldStateProvider {
            await commitCoordinator.currentState
        }
        let executor = VerifiedExecutor(
            policyEngine: bootstrapped.container.policyEngine,
            commandRouter: bootstrapped.container.commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator(),
            stateProvider: stateProvider,
            approvalStore: bootstrapped.container.approvalStore
        )
        let container = RuntimeContainer(
            planner: planner,
            executor: executor,
            commitCoordinator: commitCoordinator,
            eventStore: eventStore,
            reducer: reducer,
            policyEngine: bootstrapped.container.policyEngine,
            processAdapter: bootstrapped.container.processAdapter,
            commandRouter: bootstrapped.container.commandRouter,
            workspaceRunner: bootstrapped.container.workspaceRunner,
            repositoryIndexer: bootstrapped.container.repositoryIndexer,
            config: bootstrapped.container.config,
            traceRecorder: bootstrapped.container.traceRecorder,
            traceStore: bootstrapped.container.traceStore,
            artifactWriter: bootstrapped.container.artifactWriter,
            approvalStore: bootstrapped.container.approvalStore,
            metricsRecorder: bootstrapped.container.metricsRecorder,
            graphStore: bootstrapped.container.graphStore,
            memoryStore: bootstrapped.container.memoryStore,
            stateMemoryIndex: bootstrapped.container.stateMemoryIndex,
            searchController: bootstrapped.container.searchController,
            stateAbstraction: bootstrapped.container.stateAbstraction,
            recoveryEngine: bootstrapped.container.recoveryEngine,
            architectureEngine: bootstrapped.container.architectureEngine,
            experimentManager: bootstrapped.container.experimentManager,
            criticLoop: bootstrapped.container.criticLoop,
            stateAbstractionEngine: bootstrapped.container.stateAbstractionEngine,
            automationHost: bootstrapped.container.automationHost,
            browserController: bootstrapped.container.browserController,
            browserPageStateBuilder: bootstrapped.container.browserPageStateBuilder
        )
        return (RuntimeOrchestrator(container: container), planner, container)
    }

    private func makeWorkspace() throws -> URL {
        let root = makeTempDirectory()
        let sources = root.appendingPathComponent("Sources/Example", isDirectory: true)
        let tests = root.appendingPathComponent("Tests/ExampleTests", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        let package = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "Example",
            products: [
                .library(name: "Example", targets: ["Example"]),
            ],
            targets: [
                .target(name: "Example"),
                .testTarget(name: "ExampleTests", dependencies: ["Example"]),
            ]
        )
        """

        let source = """
        public struct Calculator {
            public static func double(_ value: Int) -> Int {
                value * 2
            }
        }
        """

        let test = """
        import Testing
        @testable import Example

        @Test func doublesInput() {
            #expect(Calculator.double(2) == 4)
        }
        """

        try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try source.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)
        try test.write(to: tests.appendingPathComponent("CalculatorTests.swift"), atomically: true, encoding: .utf8)

        try runGit(["init"], in: root)
        try runGit(["config", "user.email", "tests@example.com"], in: root)
        try runGit(["config", "user.name", "Tests"], in: root)
        try runGit(["add", "."], in: root)
        try runGit(["commit", "-m", "Initial commit"], in: root)

        return root
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func runGit(_ arguments: [String], in root: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = root
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw NSError(
                domain: "RuntimePlannerContextInjectionTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
    }
}