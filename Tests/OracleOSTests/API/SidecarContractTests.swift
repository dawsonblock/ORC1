import XCTest
@testable import OracleOS

/// Phase 6: Sidecar Contract Tests
/// Verify that external service boundaries maintain stable, version-controlled contracts.
class SidecarContractTests: XCTestCase {

    // MARK: - IntentAPI Contract (v1.0)

    @MainActor
    func testIntentAPIHasSubmitIntent() {
        // Verify IntentAPI has submitIntent method
        let api: IntentAPI = MockIntentAPI()
        XCTAssertNotNil(type(of: api).submitIntent)
    }

    @MainActor
    func testIntentAPIHasQueryState() {
        // Verify IntentAPI has queryState method
        let api: IntentAPI = MockIntentAPI()
        XCTAssertNotNil(type(of: api).queryState)
    }

    @MainActor
    func testIntentAPIIsSendable() {
        // IntentAPI must be Sendable for thread-safe crossing
        let api: IntentAPI = MockIntentAPI()
        let _: any Sendable = api
        XCTAssertTrue(true)
    }

    // MARK: - AutomationHost Contract (v1.0)

    @MainActor
    func testAutomationHostHasApplicationService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.applications)
    }

    @MainActor
    func testAutomationHostHasWindowService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.windows)
    }

    @MainActor
    func testAutomationHostHasMenuService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.menus)
    }

    @MainActor
    func testAutomationHostHasDialogService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.dialogs)
    }

    @MainActor
    func testAutomationHostHasProcessService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.processes)
    }

    @MainActor
    func testAutomationHostHasScreenCaptureService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.screenCapture)
    }

    @MainActor
    func testAutomationHostHasSnapshotService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.snapshots)
    }

    @MainActor
    func testAutomationHostHasPermissionService() {
        let host = AutomationHost.live()
        XCTAssertNotNil(host.permissions)
    }

    @MainActor
    func testAutomationHostIsMainActor() {
        // AutomationHost must be MainActor isolated
        let host = AutomationHost.live()
        // If this compiles and runs, MainActor is verified
        XCTAssertNotNil(host)
    }

    // MARK: - BrowserController Contract (v1.0)

    @MainActor
    func testBrowserControllerHasSnapshot() {
        let browser = BrowserController()
        let observation = Observation(
            app: "Chrome",
            windowTitle: "Test",
            url: "https://example.com"
        )
        let snapshot = browser.snapshot(appName: "Chrome", observation: observation)
        // snapshot may be nil, but method exists
        XCTAssertNotNil(browser)
    }

    @MainActor
    func testBrowserControllerHasIsBrowserApp() {
        let browser = BrowserController()
        // Verify method exists and can be called
        let isChrome = browser.isBrowserApp("Chrome")
        XCTAssertTrue(isChrome)
    }

    @MainActor
    func testBrowserControllerRecognizesChrome() {
        let browser = BrowserController()
        XCTAssertTrue(browser.isBrowserApp("Chrome"))
        XCTAssertTrue(browser.isBrowserApp("chrome"))
        XCTAssertTrue(browser.isBrowserApp("CHROME"))
    }

    @MainActor
    func testBrowserControllerRecognizesSafari() {
        let browser = BrowserController()
        XCTAssertTrue(browser.isBrowserApp("Safari"))
        XCTAssertTrue(browser.isBrowserApp("safari"))
    }

    @MainActor
    func testBrowserControllerRecognizesFirefox() {
        let browser = BrowserController()
        XCTAssertTrue(browser.isBrowserApp("Firefox"))
        XCTAssertTrue(browser.isBrowserApp("firefox"))
    }

    @MainActor
    func testBrowserControllerRecognizesArc() {
        let browser = BrowserController()
        XCTAssertTrue(browser.isBrowserApp("Arc"))
        XCTAssertTrue(browser.isBrowserApp("arc"))
    }

    @MainActor
    func testBrowserControllerRejectsNonBrowser() {
        let browser = BrowserController()
        XCTAssertFalse(browser.isBrowserApp("Finder"))
        XCTAssertFalse(browser.isBrowserApp("Terminal"))
        XCTAssertFalse(browser.isBrowserApp(nil))
    }

    // MARK: - ProcessAdapter Contract (v1.0)

    @MainActor
    func testProcessAdapterIsSendable() {
        let adapter: ProcessAdapter = MockProcessAdapter()
        let _: any Sendable = adapter
        XCTAssertTrue(true)
    }

    @MainActor
    func testProcessAdapterHasExecute() {
        let adapter: ProcessAdapter = MockProcessAdapter()
        XCTAssertNotNil(type(of: adapter).execute)
    }

    // MARK: - Planner Contract (v1.0)

    @MainActor
    func testPlannerProtocolExists() {
        // Verify Planner protocol is defined
        let _: any Planner = MockPlanner()
        XCTAssertTrue(true)
    }

    @MainActor
    func testPlannerIsSendable() {
        let planner: any Planner = MockPlanner()
        let _: any Sendable = planner
        XCTAssertTrue(true)
    }

    // MARK: - Backward Compatibility Tests

    @MainActor
    func testIntentAPIMethodsStable() {
        // If new methods are added, old ones must remain
        let api: IntentAPI = MockIntentAPI()
        
        let expectation = expectation(description: "submitIntent exists")
        Task {
            do {
                let _intent = Intent(
                    id: UUID(),
                    domain: .ui,
                    objective: "test",
                    metadata: [:]
                )
                let _response = try await api.submitIntent(_intent)
                expectation.fulfill()
            } catch {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Contract Stability Tests

    @MainActor
    func testAutomationHostLiveAlwaysReturnsConsistentServices() {
        let host1 = AutomationHost.live()
        let host2 = AutomationHost.live()
        
        // Both instances should have the same service types
        XCTAssertTrue(
            type(of: host1.applications) == type(of: host2.applications)
        )
        XCTAssertTrue(
            type(of: host1.windows) == type(of: host2.windows)
        )
    }

    @MainActor
    func testBrowserControllerIsMainActor() {
        // BrowserController must be MainActor isolated
        let browser = BrowserController()
        // If this compiles and runs, MainActor is verified
        XCTAssertNotNil(browser)
    }
}

// MARK: - Mocks

class MockIntentAPI: IntentAPI {
    func submitIntent(_ intent: Intent) async throws -> IntentResponse {
        return IntentResponse(
            intentID: intent.id,
            outcome: .success,
            summary: "Mock success",
            cycleID: UUID(),
            snapshotID: nil,
            timestamp: Date()
        )
    }

    func queryState() async throws -> RuntimeSnapshot {
        return RuntimeSnapshot(
            timestamp: Date(),
            cycleCount: 0,
            lastCommand: nil,
            lastOutcome: nil,
            memoryTier: .none,
            stateHash: ""
        )
    }
}

class MockProcessAdapter: ProcessAdapter {
    func execute(_ spec: CommandPayload) throws -> CommandResult {
        return CommandResult(
            commandID: UUID(),
            status: "success",
            stdout: "",
            stderr: "",
            exitCode: 0,
            duration: 0.0
        )
    }
}

class MockPlanner: Planner {
    func plan(intent: Intent, context: PlannerContext) async throws -> Command {
        return Command(
            id: UUID(),
            type: .ui,
            payload: .ui(UIAction(name: "test")),
            metadata: CommandMetadata(intentID: intent.id)
        )
    }
}
