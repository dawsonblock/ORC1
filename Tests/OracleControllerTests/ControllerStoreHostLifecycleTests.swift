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
        store.selectedControlPreset = .aiDecides

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .getHealth,
            health: nil,
            errorMessage: "Health unavailable"
        )

        store.applyHealthResponse(response)

        #expect(store.health == nil)
        #expect(store.selectedControlPreset == nil)
        #expect(store.errorMessage == "Health unavailable")
    }

    @Test
    func applyHealthResponseSyncsRuntimeControlPreset() {
        let store = ControllerStore()
        let updatedHealth = makeHealthStatus(
            storageWritable: true, controlPreset: .aiDecides, policyMode: "adaptive")

        let response = ControllerHostResponse(
            requestID: "request-1",
            command: .getHealth,
            health: updatedHealth
        )

        store.applyHealthResponse(response)

        #expect(store.health == updatedHealth)
        #expect(store.selectedControlPreset == .aiDecides)
    }

    @Test
    func applyBootstrapSyncsRuntimeControlPreset() {
        let store = ControllerStore()
        let bootstrap = DashboardBootstrap(
            session: ControllerSession(
                id: "session-1",
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                hostProcessID: 42,
                activeAppName: "Finder",
                autoRefreshEnabled: true
            ),
            snapshot: makeSnapshot(appName: "Finder"),
            health: makeHealthStatus(
                storageWritable: true, controlPreset: .fullControl, policyMode: "open"),
            recipes: [],
            traceSessions: [],
            approvals: []
        )

        store.applyBootstrap(bootstrap)

        #expect(store.selectedControlPreset == .fullControl)
        #expect(store.health?.policyMode == "open")
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
    func applySnapshotFallsBackToFocusedElementWhenSelectionDisappears() {
        let store = ControllerStore()
        store.selectedElementID = "stale-element"

        store.apply(snapshot: makeSnapshot(appName: "Finder"))

        #expect(store.selectedElementID == "finder-window")
        #expect(store.selectedElement?.id == "finder-window")
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
    func readinessSummaryPrefersHostAttentionOverOtherSignals() {
        let store = ControllerStore()
        store.health = makeHealthStatus(storageWritable: true)
        store.approvalQueue = [makeApprovalRequest(id: "approval-1")]

        store.apply(hostConnection: .failed(reason: .binaryNotFound))

        let summary = store.readinessSummary

        #expect(summary.level == .attention)
        #expect(summary.statusLabel == "Host Attention")
        #expect(summary.primaryAction == .retryHost)
    }

    @Test
    func readinessSummaryPrioritizesMissingAccessibilityBeforeApprovals() {
        let store = ControllerStore()
        store.apply(hostConnection: .connected)
        store.health = makeHealthStatus(
            storageWritable: true,
            permissions: [
                makePermissionStatus(id: "accessibility", title: "Accessibility", granted: false),
                makePermissionStatus(
                    id: "screen-recording", title: "Screen Recording", granted: true),
            ]
        )
        store.approvalQueue = [makeApprovalRequest(id: "approval-1")]

        let summary = store.readinessSummary

        #expect(summary.level == .setupRequired)
        #expect(summary.primaryAction == .openAccessibilitySettings)
        #expect(summary.statusLabel == "Finish Setup")
    }

    @Test
    func readinessSummaryKeepsUnconfiguredOptionalIntegrationsNeutral() {
        let store = ControllerStore()
        store.apply(hostConnection: .connected)
        store.health = makeHealthStatus(storageWritable: true)
        store.chatProviderStatus = ChatProviderStatus(
            providerID: "claude-local",
            displayName: "Claude Local",
            state: .setupRequired,
            configured: false,
            available: true,
            canStream: true,
            detail: "Optional"
        )

        let summary = store.readinessSummary
        let visionTask = summary.checklist.first(where: { $0.id == "vision" })
        let copilotTask = summary.checklist.first(where: { $0.id == "copilot" })

        #expect(summary.level == .ready)
        #expect(visionTask?.state == .optional)
        #expect(copilotTask?.state == .optional)
    }

    @Test
    func readinessSummaryRoutesHealthyStateToApprovalReview() {
        let store = ControllerStore()
        store.apply(hostConnection: .connected)
        store.health = makeHealthStatus(storageWritable: true)
        store.approvalQueue = [makeApprovalRequest(id: "approval-1")]

        let summary = store.readinessSummary

        #expect(summary.level == .review)
        #expect(summary.primaryAction == .reviewApprovals)
        #expect(summary.statusLabel == "Review Approvals")
    }

    @Test
    func approvalRowsTrackSubmittingAndResolvedState() {
        let store = ControllerStore()
        let approval = makeApprovalRequest(id: "approval-1")
        store.approvalQueue = [approval]

        store.markApprovalActionPending(.approve, approval: approval)

        #expect(store.approvalRows.first?.phase == .submitting(.approve))

        store.applyApprovalsResponse(
            ControllerHostResponse(
                requestID: "request-1",
                command: .approveApprovalRequest,
                approvals: []
            )
        )
        store.markApprovalActionResolved(.approve, approval: approval)

        #expect(store.approvalRows.first?.phase == .resolved(.approve))
    }

    @Test
    func actionSummariesPreserveOperatorOutcomeLanguage() {
        let store = ControllerStore()

        store.currentActionResult = ActionRunResult(
            request: ActionRequest(kind: .wait, appName: "Finder", waitCondition: "appFrontmost"),
            success: true,
            verified: false,
            message: "Condition evaluated.",
            elapsedMs: 40
        )

        #expect(store.currentActionSummary?.outcomeTitle == "Observed Wait Result")
        #expect(store.currentActionSummary?.tone == .neutral)
        #expect(
            store.currentActionSummary?.executionDetail
                == "Observed wait condition in the host bridge")

        store.currentActionResult = ActionRunResult(
            request: ActionRequest(kind: .click, appName: "Finder", query: "Open"),
            success: true,
            verified: true,
            message: "Action completed through the verified runtime path.",
            elapsedMs: 25,
            executedThroughExecutor: true
        )

        #expect(store.currentActionSummary?.outcomeTitle == "Verified Runtime Path")
        #expect(store.currentActionSummary?.tone == .good)

        store.currentActionResult = ActionRunResult(
            request: ActionRequest(kind: .click, appName: "Finder", query: "Delete"),
            success: false,
            verified: false,
            elapsedMs: 10,
            blockedByPolicy: true,
            policyMode: "confirm-risky"
        )

        #expect(store.currentActionSummary?.outcomeTitle == "Blocked By Policy")
        #expect(store.currentActionSummary?.tone == .danger)
        #expect(
            store.currentActionSummary?.contextDetail == "The current policy mode is confirm-risky."
        )

        let pendingApproval = ActionRunResult(
            request: ActionRequest(kind: .click, appName: "Finder", query: "Delete"),
            success: false,
            verified: false,
            elapsedMs: 12,
            approvalRequestID: "approval-1",
            approvalStatus: "pending"
        )
        store.currentActionResult = pendingApproval.rejectedApprovalResult()

        #expect(store.currentActionSummary?.outcomeTitle == "Approval Rejected")
        #expect(store.currentActionSummary?.tone == .danger)
        #expect(
            store.currentActionSummary?.contextDetail
                == "Approval request approval-1 was rejected before the runtime could continue."
        )

        store.currentActionResult = ActionRunResult(
            request: ActionRequest(kind: .type, appName: "Finder", query: "Name", text: "Oracle"),
            success: true,
            verified: false,
            message: "Action completed with a partial outcome.",
            failureClass: "partial_success",
            elapsedMs: 18,
            executedThroughExecutor: true
        )

        #expect(store.currentActionSummary?.outcomeTitle == "Partial Verified Outcome")
        #expect(store.currentActionSummary?.tone == .warning)

        store.currentActionResult = ActionRunResult(
            request: ActionRequest(kind: .press, appName: "Finder", key: "return"),
            success: false,
            verified: false,
            message: "Action failed.",
            failureClass: "timeout",
            elapsedMs: 65,
            executedThroughExecutor: true
        )

        #expect(store.currentActionSummary?.outcomeTitle == "Verified Runtime Failure")
        #expect(store.currentActionSummary?.tone == .danger)
        #expect(store.currentActionSummary?.contextDetail == "Failure class: timeout.")
    }

    @Test
    func approvalReviewSummaryExcludesResolvedOnlyEntriesFromWaitingState() {
        let store = ControllerStore()
        let approval = makeApprovalRequest(id: "approval-1")

        store.markApprovalActionResolved(.reject, approval: approval)

        #expect(store.activeApprovalRows.isEmpty)
        #expect(store.approvalRows.first?.phase == .resolved(.reject))
        #expect(store.approvalReviewSummary.statusLabel == "Clear")
        #expect(
            store.approvalReviewSummary.detail
                == "Recent approval decisions are now reflected in the action feed.")
    }

    @Test
    func diagnosticsInvestigationItemsRankBlockersBeforeAdvisories() {
        let store = ControllerStore()
        store.diagnostics = makeDiagnosticsSnapshot(
            architectureFindings: [
                makeArchitectureFinding(
                    id: "finding-1",
                    title: "Boundary drift",
                    severity: "critical",
                    riskScore: 0.95,
                    occurrences: 3
                )
            ],
            repositoryIndexes: [
                makeRepositoryIndex(id: "repo-1", isGitDirty: true)
            ]
        )

        let items = store.diagnosticsInvestigationItems

        #expect(items.map(\.sourceLabel) == ["Host", "Architecture", "Repository"])
        #expect(items.first?.title == "Host evidence is missing")
        #expect(items.last?.statusLabel == "Advisory")
    }

    @Test
    func clearChatConversationDoesNothingWhileResponseIsStreaming() {
        let store = ControllerStore()
        store.chatConversation = ChatConversation(
            id: "conversation-1",
            title: "Copilot",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messages: [
                ChatMessage(
                    id: "assistant-1",
                    role: .assistant,
                    content: "",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    isStreaming: true
                )
            ]
        )
        store.chatInput = "keep this"

        store.clearChatConversation()

        #expect(store.chatConversation?.id == "conversation-1")
        #expect(store.chatInput == "keep this")
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
private func makeHealthStatus(
    storageWritable: Bool,
    permissions: [PermissionStatus] = [
        makePermissionStatus(id: "accessibility", title: "Accessibility", granted: true),
        makePermissionStatus(id: "screen-recording", title: "Screen Recording", granted: true),
    ],
    controlPreset: RuntimeControlPreset = .original,
    policyMode: String = "confirm-risky"
) -> HealthStatus {
    HealthStatus(
        runtimeVersion: "1.0.0",
        permissions: permissions,
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
        controlPreset: controlPreset,
        policyMode: policyMode,
        runningFromAppBundle: false,
        bundledHostAvailable: false,
        bundledVisionBootstrapAvailable: false,
        visionInstallPath: "/tmp/oracle/vision",
        buildVersion: "1.0.0",
        buildNumber: "1"
    )
}

@MainActor
private func makePermissionStatus(id: String, title: String, granted: Bool) -> PermissionStatus {
    PermissionStatus(
        id: id,
        title: title,
        granted: granted,
        detail: granted ? "Granted" : "Still required"
    )
}

@MainActor
private func makeDiagnosticsSnapshot(
    graph: ControllerGraphDiagnostics = ControllerGraphDiagnostics(
        stableEdges: [],
        candidateEdges: [],
        recoveryEdges: [],
        promotionEligibleCount: 0,
        promotionsFrozen: false,
        globalSuccessRate: 0
    ),
    workflows: [ControllerWorkflowDiagnostics] = [],
    experiments: [ControllerExperimentDiagnostics] = [],
    recovery: ControllerRecoveryDiagnostics = ControllerRecoveryDiagnostics(
        recoveryStepCount: 0,
        strategies: []
    ),
    projectMemory: [ControllerProjectMemoryDiagnostics] = [],
    architectureFindings: [ControllerArchitectureFindingDiagnostics] = [],
    repositoryIndexes: [ControllerRepositoryIndexDiagnostics] = [],
    host: ControllerHostDiagnostics? = nil,
    browser: ControllerBrowserDiagnostics? = nil
) -> ControllerDiagnosticsSnapshot {
    ControllerDiagnosticsSnapshot(
        graph: graph,
        workflows: workflows,
        experiments: experiments,
        recovery: recovery,
        projectMemory: projectMemory,
        architectureFindings: architectureFindings,
        repositoryIndexes: repositoryIndexes,
        host: host,
        browser: browser
    )
}

@MainActor
private func makeTraceDetail(id: String) -> TraceSessionDetail {
    let summary = TraceSessionSummary(
        id: id, stepCount: 1, lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
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
        latencySeries: DashboardSeries(
            id: "latency", title: "Latency", subtitle: "Recent", points: []),
        successSeries: DashboardSeries(
            id: "success", title: "Success", subtitle: "Recent", points: []),
        workflowSeries: DashboardSeries(
            id: "workflow", title: "Workflow", subtitle: "Recent", points: []),
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
private func makeArchitectureFinding(
    id: String,
    title: String,
    severity: String,
    riskScore: Double,
    occurrences: Int
) -> ControllerArchitectureFindingDiagnostics {
    ControllerArchitectureFindingDiagnostics(
        id: id,
        title: title,
        summary: "Summary for \(title)",
        severity: severity,
        affectedModules: ["OracleController"],
        evidence: ["evidence"],
        riskScore: riskScore,
        occurrences: occurrences,
        governanceRuleID: nil
    )
}

@MainActor
private func makeRepositoryIndex(id: String, isGitDirty: Bool)
    -> ControllerRepositoryIndexDiagnostics
{
    ControllerRepositoryIndexDiagnostics(
        id: id,
        workspaceRoot: "/tmp/oracle/repo",
        buildTool: "swiftpm",
        activeBranch: "main",
        isGitDirty: isGitDirty,
        indexedAt: Date(timeIntervalSince1970: 1_700_000_000),
        fileCount: 42,
        symbolCount: 128,
        dependencyCount: 16,
        callEdgeCount: 32,
        testEdgeCount: 8,
        buildTargetCount: 3,
        topSymbols: ["ControllerStore"],
        buildTargets: ["OracleController"],
        topTests: ["ControllerStoreHostLifecycleTests"]
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
