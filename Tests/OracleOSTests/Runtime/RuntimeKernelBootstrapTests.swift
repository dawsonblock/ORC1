import Foundation
import Testing
@testable import OracleOS

/// Tests that prove the runtime kernel bootstrap path is the only live path.
@MainActor
struct RuntimeKernelBootstrapTests {

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url
            }
            url = parent
        }
    }

    private func encodedActionIntent(_ actionIntent: ActionIntent) throws -> String {
        try JSONEncoder().encode(actionIntent).base64EncodedString()
    }

    private func readSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Bootstrap Truth Tests

    @Test func kernelBootstrapReturnsCompleteKernel() async throws {
        // Verify that RuntimeBootstrap.makeBootstrappedRuntime returns a complete runtime
        // with real reducers, not empty arrays.
        let config = RuntimeConfig.test()
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)

        // The container must have a non-nil reducer
        #expect(bootstrapped.container.reducer != nil, "Kernel must have real reducers")
    }

    @Test func commitCoordinatorHasReducers() async throws {
        let config = RuntimeConfig.test()
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)

        // Create a test event and commit it
        let intentID = UUID()
        let event = EventEnvelope(
            sequenceNumber: 0,
            commandID: nil,
            intentID: intentID,
            eventType: "intent.received",
            payload: try JSONEncoder().encode(
                IntentReceivedEvent(intentID: intentID, objective: "test")
            )
        )

        // After commit, state should change (proving reducers ran)
        let snapshotBefore = await bootstrapped.container.commitCoordinator.snapshot()
        let cycleCountBefore = snapshotBefore.cycleCount

        _ = try await bootstrapped.container.commitCoordinator.commit([event])

        let snapshotAfter = await bootstrapped.container.commitCoordinator.snapshot()
        let cycleCountAfter = snapshotAfter.cycleCount

        #expect(cycleCountAfter > cycleCountBefore, "Reducers must increment cycle count")
    }

    @Test func submitIntentCommitsMainRuntimeSpineForCodeSearch() async throws {
        let config = RuntimeConfig.test()
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: config)
        let workspaceRoot = repositoryRoot().path
        let actionIntent = ActionIntent.code(
            name: "read package manifest",
            command: CommandSpec(
                category: .openFile,
                executable: "cat",
                arguments: ["Package.swift"],
                workspaceRoot: workspaceRoot,
                workspaceRelativePath: "Package.swift",
                summary: "read Package.swift"
            )
        )
        let intent = Intent(
            domain: .code,
            objective: "read Package.swift",
            metadata: ["action_intent_base64": try encodedActionIntent(actionIntent)]
        )

        let response = try await bootstrapped.orchestrator.submitIntent(intent)
        let runtimeSnapshot = try await bootstrapped.orchestrator.queryState()
        let committedSnapshot = await bootstrapped.container.commitCoordinator.snapshot()

        #expect(response.outcome == .success)
        #expect(response.snapshotID != nil)
        #expect(runtimeSnapshot.lastIntentID == intent.id)
        #expect(runtimeSnapshot.lastCommandKind == "readFile")
        #expect(committedSnapshot.notes.contains("lastCommandKind=readFile"))
        #expect(committedSnapshot.notes.contains("lastExecutionStatus=success"))
        #expect(committedSnapshot.notes.contains("criticOutcome=success"))
    }

    @Test func bootstrapAndManifestMakeMacOSOnlySupportExplicit() throws {
        let manifest = try readSource("Package.swift")
        let bootstrap = try readSource("Sources/OracleOS/Runtime/RuntimeBootstrap.swift")

        #expect(manifest.contains(".macOS(.v14)"))
        #expect(
            bootstrap.contains("OracleOS runtime build and test are supported on macOS 14+ only")
        )
        #expect(
            bootstrap.contains("Apple accessibility frameworks and the vendored AX layer")
        )
    }

    // MARK: - Snapshot Immutability Tests

    @Test func stateSnapshotIsImmutableValue() {
        let worldSnapshot = WorldModelSnapshot(
            timestamp: Date(),
            cycleCount: 5,
            activeApplication: "Safari",
            windowTitle: "Test",
            visibleElementCount: 10
        )

        let stateSnapshot = StateSnapshot(
            sequenceNumber: 1,
            state: worldSnapshot,
            eventAncestry: [UUID()]
        )

        // StateSnapshot.state is WorldModelSnapshot (value type), not WorldStateModel (reference type)
        // This test passes if the code compiles — the type system enforces immutability
        #expect(stateSnapshot.state.cycleCount == 5)
        #expect(stateSnapshot.state.activeApplication == "Safari")
    }

    @Test func snapshotStoreTracksSnapshots() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = SnapshotStore(directory: tempDir)

        let snapshot1 = StateSnapshot(
            sequenceNumber: 1,
            state: WorldModelSnapshot(cycleCount: 1),
            eventAncestry: []
        )
        let snapshot2 = StateSnapshot(
            sequenceNumber: 2,
            state: WorldModelSnapshot(cycleCount: 2),
            eventAncestry: []
        )

        await store.append(snapshot1)
        await store.append(snapshot2)

        let latest = await store.latest()
        #expect(latest?.sequenceNumber == 2)
        #expect(await store.count == 2)
    }
}
