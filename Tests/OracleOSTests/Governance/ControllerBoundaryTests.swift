import XCTest

@testable import OracleOS

/// Verifies that OracleController/OracleControllerHost only access the runtime
/// through the IntentAPI protocol — not planners, executors, or runtime internals.
final class ControllerBoundaryTests: XCTestCase {

    // MARK: - Helpers

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    private func swiftFiles(under directory: String) -> [URL] {
        let root = repositoryRoot().appendingPathComponent(directory, isDirectory: true)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    // MARK: - Tests

    /// IntentResponse and RuntimeSnapshot must be defined in the API layer only.
    func test_api_types_are_in_api_module() {
        // These types should be constructable without importing runtime internals
        let response = IntentResponse(
            intentID: UUID(), outcome: .skipped, summary: "test", cycleID: UUID())
        let snapshot = RuntimeSnapshot(timestamp: Date(), status: .idle, summary: "test")
        XCTAssertNotNil(response)
        XCTAssertNotNil(snapshot)
    }

    /// RuntimeOrchestrator must conform to IntentAPI — it is the sole implementation.
    @MainActor
    func test_runtime_orchestrator_conforms_to_intent_api() async throws {
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(
            configuration: .test())
        let orchestrator = bootstrapped.orchestrator

        // RuntimeOrchestrator must be usable as IntentAPI — this is the controller boundary
        let api: any IntentAPI = orchestrator
        XCTAssertNotNil(api)
    }

    /// Controller source files must not directly call into Planning internals.
    func test_controller_host_does_not_call_planners_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "planner.nextStep(",
            "planner.plan(",
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' — use submitIntent() instead"
                )
            }
        }
    }

    /// Controller source files must not directly call executor.execute().
    func test_controller_host_does_not_call_executor_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "VerifiedExecutor(",
            "verifiedExecutor.execute(",
            "commandRouter.execute(",
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' directly — use IntentAPI"
                )
            }
        }
    }

    /// AutomationHost may only be used for observational snapshots from the host bridge.
    func test_controller_runtime_bridge_uses_automation_host_only_for_snapshots() throws {
        let bridgeFile = repositoryRoot().appendingPathComponent(
            "Sources/OracleControllerHost/ControllerRuntimeBridge.swift")
        let content = try String(contentsOf: bridgeFile)

        let automationHostOccurrences = content.components(separatedBy: "automationHost").count - 1
        XCTAssertEqual(
            automationHostOccurrences, 1,
            "ControllerRuntimeBridge should reference AutomationHost exactly once")
        XCTAssertTrue(
            content.contains("container.automationHost.snapshots.captureSnapshot("),
            "AutomationHost usage in ControllerRuntimeBridge must stay observational-only")
    }

    /// WaitManager is the only direct non-executor action path allowed in the host bridge.
    func test_controller_runtime_bridge_limits_direct_wait_manager_usage() throws {
        let bridgeFile = repositoryRoot().appendingPathComponent(
            "Sources/OracleControllerHost/ControllerRuntimeBridge.swift")
        let content = try String(contentsOf: bridgeFile)

        let waitOccurrences = content.components(separatedBy: "WaitManager.waitFor(").count - 1
        XCTAssertEqual(
            waitOccurrences, 1,
            "ControllerRuntimeBridge should contain a single explicit WaitManager bypass")

        guard let waitStart = content.range(of: "case .wait:"),
            let waitEnd = content.range(
                of: "return mapActionResult(request: request, result: result)",
                range: waitStart.upperBound..<content.endIndex
            )
        else {
            XCTFail("Could not isolate the .wait case in ControllerRuntimeBridge.swift")
            return
        }

        let waitCase = String(content[waitStart.lowerBound..<waitEnd.lowerBound])
        let nonCommentWaitCase =
            waitCase
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//")
            }
            .joined(separator: "\n")

        XCTAssertTrue(
            nonCommentWaitCase.contains("WaitManager.waitFor("),
            "Wait case must stay host-local through WaitManager")
        XCTAssertFalse(
            nonCommentWaitCase.contains("Actions."),
            "Wait case must stay observational and must not dispatch UI actions")
        XCTAssertFalse(
            nonCommentWaitCase.contains("oracleRuntime"),
            "Wait case must not route through the runtime orchestrator")
        XCTAssertFalse(
            nonCommentWaitCase.contains("submitIntent("),
            "Wait case must not submit an intent into the main execution spine")
        XCTAssertFalse(
            nonCommentWaitCase.contains("VerifiedExecutor"),
            "Wait case must not reference executor authority")
    }

    /// Controller host mapping must consume typed ToolResult views instead of
    /// re-probing legacy data dictionaries for action or recipe fields.
    func test_controller_runtime_bridge_avoids_legacy_toolresult_fallback_probes() throws {
        let bridgeFile = repositoryRoot().appendingPathComponent(
            "Sources/OracleControllerHost/ControllerRuntimeBridge.swift")
        let mappingFile = repositoryRoot().appendingPathComponent(
            "Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift")

        let bridgeContent = try String(contentsOf: bridgeFile)
        let mappingContent = try String(contentsOf: mappingFile)

        XCTAssertFalse(
            mappingContent.contains("result.data?[ActionResultKey.method]"),
            "ControllerRuntimeBridge+Mapping must use result.actionResult.method instead of re-reading legacy data"
        )
        XCTAssertFalse(
            bridgeContent.contains("result.data?[RecipeResultKey.recipe]"),
            "ControllerRuntimeBridge must use result.recipeRunResult.recipeName instead of re-reading legacy data"
        )
    }

    /// Controller source files must not commit events directly.
    func test_controller_host_does_not_commit_events_directly() {
        let controllerFiles = swiftFiles(under: "Sources/OracleControllerHost")
        let bannedPatterns = [
            "commitCoordinator.commit(",
            "eventStore.append(",
        ]

        for url in controllerFiles {
            guard let content = try? String(contentsOf: url) else { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (controller host) must not call '\(pattern)' directly"
                )
            }
        }
    }

    func test_code_intents_do_not_emit_ui_payloads() throws {
        let sourcePath = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/Planning/MainPlanner+Planner.swift")
        guard let text = try? String(contentsOf: sourcePath, encoding: .utf8) else { return }
        XCTAssertFalse(
            text.contains("type: .code, payload: .ui")
                || text.contains("Command(type: .code, payload: .ui"),
            "MainPlanner emits .ui for .code")
    }

}
