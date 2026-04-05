import Foundation
import Testing
@testable import OracleController
@testable import OracleControllerShared

@MainActor
struct ControllerStoreHostLifecycleTests {
    @Test
    func applyHostConnectionSurfacesLaunchFailure() {
        let store = ControllerStore()
        let failure = HostConnectionStatus.failed(reason: .binaryNotFound)

        store.apply(hostConnection: failure)

        #expect(store.hostConnection == failure)
        #expect(store.errorMessage == failure.detailText)
        #expect(store.isBusy == false)
    }

    @Test
    func applyHostConnectionClearsMatchingHostErrorOnReconnect() {
        let store = ControllerStore()
        let failure = HostConnectionStatus.disconnected(
            reason: .exited,
            detail: "OracleControllerHost exited with status 15."
        )

        store.apply(hostConnection: failure)
        store.apply(hostConnection: .connected)

        #expect(store.hostConnection == .connected)
        #expect(store.errorMessage == nil)
        #expect(store.inlineMessage == "OracleControllerHost reconnected.")
    }

    @Test
    func presentMapsHostClientErrorsToHostConnectionState() {
        let store = ControllerStore()
        let error = HostClientError.hostBinaryNotRunnable(path: "/tmp/OracleControllerHost")

        store.present(error)

        #expect(store.hostConnection.phase == .failed)
        #expect(store.hostConnection.failureReason == .binaryNotRunnable)
        #expect(store.errorMessage == error.errorDescription)
    }

    @Test
    func requireAcknowledgedUsesResponseErrorMessage() {
        let store = ControllerStore()
        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .approveApprovalRequest,
            acknowledged: false,
            errorMessage: "Approval expired"
        )

        let acknowledged = store.requireAcknowledged(response, fallback: "Approval failed")

        #expect(acknowledged == false)
        #expect(store.errorMessage == "Approval expired")
    }

    @Test
    func recordRecipeRunStoresPausedApprovalState() {
        let store = ControllerStore()
        let approvals = [
            ApprovalRequestDocument(
                id: "approval-1",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                surface: "controller",
                toolName: "oracle_click",
                appName: "Finder",
                displayTitle: "Approve click",
                reason: "Delete confirmation",
                riskLevel: "high",
                protectedOperation: "destructive",
                status: "pending",
                appProtectionProfile: "default"
            )
        ]
        let recipeRun = RecipeRunResultDocument(
            recipeName: "gmail-send",
            success: false,
            stepsCompleted: 2,
            totalSteps: 4,
            stepResults: [],
            paused: true,
            pendingApprovalRequestID: "approval-1",
            resumeToken: "resume-1"
        )

        store.recordRecipeRun(recipeRun, approvals: approvals)

        #expect(store.latestRecipeRun == recipeRun)
        #expect(store.approvalQueue == approvals)
        #expect(store.inlineMessage == recipeRun.summaryText)
    }

    @Test
    func applyHealthResponseClearsStaleHealthWhenPayloadMissing() {
        let store = ControllerStore()
        store.health = makeHealthStatus(storageWritable: true)

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .getHealth,
            health: nil,
            errorMessage: "Health unavailable"
        )

        store.applyHealthResponse(response)

        #expect(store.health == nil)
        #expect(store.errorMessage == "Health unavailable")
    }

    @Test
    func applySnapshotResponseClearsStaleSnapshotWhenPayloadMissing() {
        let store = ControllerStore()
        store.snapshot = makeSnapshot(appName: "Finder")
        store.selectedElementID = "finder-window"

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .refreshSnapshot,
            snapshot: nil,
            errorMessage: "Snapshot unavailable"
        )

        store.applySnapshotResponse(response)

        #expect(store.snapshot == nil)
        #expect(store.selectedElementID == nil)
        #expect(store.errorMessage == "Snapshot unavailable")
    }

    @Test
    func applyDiagnosticsResponseClearsSelectionsWhenPayloadMissing() {
        let store = ControllerStore()
        store.diagnostics = makeDiagnosticsSnapshot()
        store.selectedGraphEdgeID = "edge-1"
        store.selectedWorkflowID = "workflow-1"
        store.selectedExperimentID = "experiment-1"
        store.selectedProjectMemoryID = "memory-1"
        store.selectedArchitectureFindingID = "finding-1"

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .getDiagnostics,
            diagnostics: nil,
            errorMessage: "Diagnostics unavailable"
        )

        store.applyDiagnosticsResponse(response)

        #expect(store.diagnostics == nil)
        #expect(store.selectedGraphEdgeID == nil)
        #expect(store.selectedWorkflowID == nil)
        #expect(store.selectedExperimentID == nil)
        #expect(store.selectedProjectMemoryID == nil)
        #expect(store.selectedArchitectureFindingID == nil)
        #expect(store.errorMessage == "Diagnostics unavailable")
    }

    @Test
    func applyTraceDetailResponseClearsStaleTraceWhenPayloadMissing() {
        let store = ControllerStore()
        store.traceDetail = makeTraceDetail(id: "trace-old")
        store.selectedTraceSessionID = "trace-old"
        store.selectedTraceStepID = "trace-old-1"

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .loadTraceSession,
            traceDetail: nil,
            errorMessage: "Trace missing"
        )

        let applied = store.applyTraceDetailResponse(response, requestedID: "trace-new")

        #expect(applied == false)
        #expect(store.traceDetail == nil)
        #expect(store.selectedTraceSessionID == "trace-new")
        #expect(store.selectedTraceStepID == nil)
        #expect(store.selectedSection == .traces)
        #expect(store.errorMessage == "Trace missing")
    }

    @Test
    func applyMissionControlResponseClearsStaleDashboardWhenPayloadMissing() {
        let store = ControllerStore()
        store.missionControl = makeMissionControlSnapshot()
        store.chatProviderStatus = ChatProviderStatus(
            providerID: "claude-local",
            displayName: "Claude Local",
            state: .ready,
            configured: true,
            available: true,
            canStream: true,
            detail: "Ready"
        )

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .refreshMissionControl,
            missionControl: nil,
            chatProviderStatus: ChatProviderStatus(
                providerID: "claude-local",
                displayName: "Claude Local",
                state: .setupRequired,
                configured: false,
                available: true,
                canStream: true,
                detail: "Optional"
            ),
            errorMessage: "Mission Control unavailable"
        )

        store.applyMissionControlResponse(response)

        #expect(store.missionControl == nil)
        #expect(store.chatProviderStatus?.state == .setupRequired)
        #expect(store.errorMessage == "Mission Control unavailable")
    }

    @Test
    func applyApprovalsResponseClearsStaleQueueWhenPayloadMissing() {
        let store = ControllerStore()
        store.approvalQueue = [makeApprovalRequest(id: "approval-1")]

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .listApprovalRequests,
            approvals: nil,
            errorMessage: "Approvals unavailable"
        )

        store.applyApprovalsResponse(response)

        #expect(store.approvalQueue.isEmpty)
        #expect(store.errorMessage == "Approvals unavailable")
    }

    @Test
    func applyRecipesResponseClearsStaleRecipeSelectionWhenPayloadMissing() {
        let store = ControllerStore()
        let recipe = makeRecipe(name: "gmail-send")
        store.recipes = [recipe]
        store.apply(recipe: recipe)

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .listRecipes,
            recipes: nil,
            errorMessage: "Recipes unavailable"
        )

        store.applyRecipesResponse(response)

        #expect(store.recipes.isEmpty)
        #expect(store.selectedRecipeName == nil)
        #expect(store.draftRecipe.name != "gmail-send")
        #expect(store.errorMessage == "Recipes unavailable")
    }

    @Test
    func applyRecipeResponseClearsSelectedRecipeWhenRequestedRecipeMissing() {
        let store = ControllerStore()
        let recipe = makeRecipe(name: "gmail-send")
        store.apply(recipe: recipe)

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .loadRecipe,
            recipe: nil,
            errorMessage: "Recipe missing"
        )

        let applied = store.applyRecipeResponse(response, requestedName: "gmail-send")

        #expect(applied == false)
        #expect(store.selectedRecipeName == nil)
        #expect(store.draftRecipe.name != "gmail-send")
        #expect(store.errorMessage == "Recipe missing")
    }
}

@MainActor
private func makeHealthStatus(storageWritable: Bool) -> HealthStatus {
    HealthStatus(
        runtimeVersion: "1.0.0",
        permissions: [],
        claudeConfigured: false,
        visionSidecarRunning: false,
        recipeDirectoryPath: "/tmp/oracle/recipes",
        recipeCount: 0,
        traceDirectoryPath: "/tmp/oracle/traces",
        applicationSupportPath: "/tmp/oracle",
        approvalsDirectoryPath: "/tmp/oracle/approvals",
        projectMemoryDirectoryPath: "/tmp/oracle/project-memory",
        experimentsDirectoryPath: "/tmp/oracle/experiments",
        logsDirectoryPath: "/tmp/oracle/logs",
        graphDatabasePath: "/tmp/oracle/graph/oracleos.sqlite3",
        storageLocations: [
            StorageLocationStatus(
                id: "app-support",
                title: "Application Support",
                path: "/tmp/oracle",
                writable: storageWritable,
                detail: storageWritable ? nil : "Current user cannot write to this path."
            )
        ],
        approvalBrokerActive: true,
        controllerConnected: true,
        policyMode: "standard",
        runningFromAppBundle: false,
        bundledHostAvailable: false,
        bundledVisionBootstrapAvailable: false,
        visionInstallPath: "/tmp/oracle/vision",
        buildVersion: "1.0.0",
        buildNumber: "1"
    )
}

@MainActor
private func makeDiagnosticsSnapshot() -> ControllerDiagnosticsSnapshot {
    ControllerDiagnosticsSnapshot(
        graph: ControllerGraphDiagnostics(
            stableEdges: [],
            candidateEdges: [],
            recoveryEdges: [],
            promotionEligibleCount: 0,
            promotionsFrozen: false,
            globalSuccessRate: 0
        ),
        workflows: [],
        experiments: [],
        recovery: ControllerRecoveryDiagnostics(recoveryStepCount: 0, strategies: []),
        projectMemory: [],
        architectureFindings: [],
        repositoryIndexes: []
    )
}

@MainActor
private func makeTraceDetail(id: String) -> TraceSessionDetail {
    let summary = TraceSessionSummary(id: id, stepCount: 1, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
    let step = TraceStepViewModel(
        sessionID: id,
        stepID: 1,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        toolName: "oracle_focus",
        actionName: "focus",
        actionTarget: "Finder",
        actionText: nil,
        selectedElementID: nil,
        selectedElementLabel: nil,
        candidateScore: nil,
        candidateReasons: [],
        preObservationHash: nil,
        postObservationHash: nil,
        postcondition: nil,
        verified: true,
        success: true,
        failureClass: nil,
        elapsedMs: 42,
        screenshotPath: nil,
        artifactPaths: [],
        notes: nil
    )
    return TraceSessionDetail(summary: summary, steps: [step])
}

@MainActor
private func makeMissionControlSnapshot() -> MissionControlSnapshot {
    MissionControlSnapshot(
        kpis: [],
        latencySeries: DashboardSeries(id: "latency", title: "Latency", subtitle: "Recent", points: []),
        successSeries: DashboardSeries(id: "success", title: "Success", subtitle: "Recent", points: []),
        workflowSeries: DashboardSeries(id: "workflow", title: "Workflow", subtitle: "Recent", points: []),
        recentActivity: [],
        alerts: [],
        approvals: [],
        workflows: [],
        experiments: [],
        traceSessions: [],
        repositoryIndexes: [],
        health: makeHealthStatus(storageWritable: true),
        snapshot: nil,
        host: nil,
        browser: nil,
        providerStatus: ChatProviderStatus(
            providerID: "claude-local",
            displayName: "Claude Local",
            state: .ready,
            configured: true,
            available: true,
            canStream: true,
            detail: "Ready"
        ),
        recommendedPrompts: []
    )
}

@MainActor
private func makeSnapshot(appName: String) -> ControlSnapshot {
    ControlSnapshot(
        observation: ObservationSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            appName: appName,
            windowTitle: "Window",
            focusedElementID: "finder-window",
            elements: [
                ElementSnapshot(
                    id: "finder-window",
                    source: "ax",
                    role: "window",
                    label: "Finder",
                    enabled: true,
                    visible: true,
                    focused: true,
                    confidence: 1
                )
            ]
        )
    )
}

@MainActor
private func makeApprovalRequest(id: String) -> ApprovalRequestDocument {
    ApprovalRequestDocument(
        id: id,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        surface: "controller",
        toolName: "oracle_click",
        appName: "Finder",
        displayTitle: "Approve click",
        reason: "Delete confirmation",
        riskLevel: "high",
        protectedOperation: "destructive",
        status: "pending",
        appProtectionProfile: "default"
    )
}

@MainActor
private func makeRecipe(name: String) -> RecipeDocument {
    RecipeDocument(
        name: name,
        description: "Recipe",
        app: "Finder",
        steps: [RecipeStepDocument(id: 1, action: "focus")]
    )
}