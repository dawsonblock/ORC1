// ControllerStore+Internal.swift — Internal helpers: event handling, state application, and run bookkeeping.

import Foundation
import OracleControllerShared

extension ControllerStore {
    func present(_ error: any Error) {
        if let hostError = error as? HostClientError,
           let status = hostError.connectionStatus
        {
            apply(hostConnection: status)
        }

        errorMessage = error.localizedDescription
    }

    func handle(_ event: ControllerHostEvent) {
        switch event.kind {
        case .actionStarted:
            isBusy = true
            inlineMessage = event.message
            session = event.session ?? session

        case .actionCompleted:
            isBusy = false
            session = event.session ?? session
            if let action = event.action {
                record(action)
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .observationUpdated:
            session = event.session ?? session
            if let snapshot = event.snapshot {
                apply(snapshot: snapshot)
            }

        case .traceStepAppended:
            if let traceStep = event.traceStep {
                append(traceStep)
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .healthChanged:
            session = event.session ?? session
            if let health = event.health {
                apply(health: health)
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .recipesChanged:
            if let recipes = event.recipes {
                self.recipes = recipes
                syncSelectionAfterRecipeRefresh()
            }

        case .approvalsChanged:
            if let approvals = event.approvals {
                approvalQueue = approvals
            }

        case .missionControlChanged:
            if let missionControl = event.missionControl {
                self.missionControl = missionControl
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }

        case .chatStreamDelta:
            if let conversation = event.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }

        case .chatMessageCompleted:
            if let conversation = event.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
        }
    }

    func apply(hostConnection status: HostConnectionStatus) {
        let previous = hostConnection
        guard previous != status else { return }

        hostConnection = status

        if status.requiresAttention {
            isBusy = false
            if errorMessage == nil || previous.requiresAttention || errorMessage == previous.detailText {
                errorMessage = status.detailText
            }
            return
        }

        if status.isConnected,
           previous.requiresAttention,
           errorMessage == previous.detailText
        {
            errorMessage = nil
            inlineMessage = "OracleControllerHost reconnected."
        }
    }

    func bootstrapHost() async throws {
        let response = try await send(.init(command: .bootstrap, appName: monitorAppName.nilIfBlank))
        applyBootstrap(response.bootstrap)
    }

    @discardableResult
    func requireAcknowledged(_ response: ControllerHostResponse, fallback: String) -> Bool {
        guard response.acknowledged else {
            errorMessage = response.errorMessage ?? fallback
            return false
        }
        return true
    }

    func recordRecipeRun(_ recipeRun: RecipeRunResultDocument, approvals: [ApprovalRequestDocument]?) {
        latestRecipeRun = recipeRun
        inlineMessage = recipeRun.summaryText
        if let approvals {
            approvalQueue = approvals
        }
    }

    func applyHealthResponse(_ response: ControllerHostResponse, fallback: String = "Health snapshot unavailable") {
        guard let health = response.health else {
            self.health = nil
            selectedControlPreset = nil
            errorMessage = response.errorMessage ?? fallback
            return
        }

        apply(health: health)
    }

    func applySnapshotResponse(_ response: ControllerHostResponse, fallback: String = "Observation snapshot unavailable") {
        guard let snapshot = response.snapshot else {
            self.snapshot = nil
            selectedElementID = nil
            errorMessage = response.errorMessage ?? fallback
            return
        }

        apply(snapshot: snapshot)
    }

    func applyDiagnosticsResponse(_ response: ControllerHostResponse, fallback: String = "Diagnostics snapshot unavailable") {
        guard let diagnostics = response.diagnostics else {
            self.diagnostics = nil
            selectedGraphEdgeID = nil
            selectedWorkflowID = nil
            selectedExperimentID = nil
            selectedProjectMemoryID = nil
            selectedArchitectureFindingID = nil
            errorMessage = response.errorMessage ?? fallback
            return
        }

        self.diagnostics = diagnostics
        selectedGraphEdgeID = selectedGraphEdgeID
            ?? diagnostics.graph.stableEdges.first?.id
            ?? diagnostics.graph.candidateEdges.first?.id
            ?? diagnostics.graph.recoveryEdges.first?.id
        selectedWorkflowID = selectedWorkflowID ?? diagnostics.workflows.first?.id
        selectedExperimentID = selectedExperimentID ?? diagnostics.experiments.first?.id
        selectedProjectMemoryID = selectedProjectMemoryID ?? diagnostics.projectMemory.first?.id
        selectedArchitectureFindingID = selectedArchitectureFindingID ?? diagnostics.architectureFindings.first?.id
    }

    func applyTraceSessionsResponse(_ response: ControllerHostResponse, fallback: String = "Trace list unavailable") {
        guard let traceSessions = response.traceSessions else {
            self.traceSessions = []
            selectedTraceSessionID = nil
            traceDetail = nil
            selectedTraceStepID = nil
            errorMessage = response.errorMessage ?? fallback
            return
        }

        self.traceSessions = traceSessions
        let currentSelectionStillExists = selectedTraceSessionID.map { id in
            traceSessions.contains(where: { $0.id == id })
        } ?? false

        if !currentSelectionStillExists {
            selectedTraceSessionID = traceSessions.first?.id
            traceDetail = nil
            selectedTraceStepID = nil
        }
    }

    @discardableResult
    func applyTraceDetailResponse(
        _ response: ControllerHostResponse,
        requestedID: String,
        fallback: String = "Trace not found"
    ) -> Bool {
        guard let traceDetail = response.traceDetail else {
            self.traceDetail = nil
            self.selectedTraceSessionID = requestedID
            self.selectedTraceStepID = nil
            self.selectedSection = .traces
            errorMessage = response.errorMessage ?? fallback
            return false
        }

        self.traceDetail = traceDetail
        self.selectedTraceSessionID = requestedID
        self.selectedTraceStepID = traceDetail.steps.first?.id
        self.selectedSection = .traces
        return true
    }

    func applyApprovalsResponse(_ response: ControllerHostResponse, fallback: String = "Approval list unavailable") {
        guard let approvals = response.approvals else {
            approvalQueue = []
            errorMessage = response.errorMessage ?? fallback
            return
        }

        approvalQueue = approvals
    }

    func applyMissionControlResponse(_ response: ControllerHostResponse, fallback: String = "Mission Control snapshot unavailable") {
        guard let missionControl = response.missionControl else {
            self.missionControl = nil
            if let providerStatus = response.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
            errorMessage = response.errorMessage ?? fallback
            return
        }

        self.missionControl = missionControl
        chatProviderStatus = response.chatProviderStatus ?? missionControl.providerStatus
    }

    func applyRecipesResponse(_ response: ControllerHostResponse, fallback: String = "Recipe library unavailable") {
        guard let recipes = response.recipes else {
            self.recipes = []
            if selectedRecipeName != nil {
                createRecipe()
            }
            errorMessage = response.errorMessage ?? fallback
            return
        }

        self.recipes = recipes
        syncSelectionAfterRecipeRefresh()
    }

    @discardableResult
    func applyRecipeResponse(
        _ response: ControllerHostResponse,
        requestedName: String,
        fallback: String = "Recipe not found"
    ) -> Bool {
        guard let recipe = response.recipe else {
            if selectedRecipeName == requestedName || draftRecipe.name == requestedName {
                createRecipe()
            } else {
                selectedRecipeName = nil
            }
            errorMessage = response.errorMessage ?? fallback
            return false
        }

        apply(recipe: recipe)
        return true
    }

    func applyBootstrap(_ bootstrap: DashboardBootstrap?) {
        guard let bootstrap else { return }
        session = bootstrap.session
        snapshot = bootstrap.snapshot
        apply(health: bootstrap.health)
        recipes = bootstrap.recipes
        traceSessions = bootstrap.traceSessions
        approvalQueue = bootstrap.approvals
        missionControl = bootstrap.missionControl
        chatConversation = bootstrap.chatConversation
        chatProviderStatus = bootstrap.chatProviderStatus ?? bootstrap.missionControl?.providerStatus
        selectedElementID = bootstrap.snapshot?.observation.focusedElementID
        actionComposer.hydrate(from: bootstrap.snapshot)
        if monitorAppName.isEmpty {
            monitorAppName = bootstrap.session.activeAppName ?? bootstrap.snapshot?.observation.appName ?? ""
        }
        if selectedRecipeName == nil, let recipe = bootstrap.recipes.first {
            apply(recipe: recipe)
        }
        if selectedTraceSessionID == nil {
            selectedTraceSessionID = bootstrap.traceSessions.first?.id
        }
    }

    func apply(snapshot: ControlSnapshot) {
        self.snapshot = snapshot
        selectedElementID = snapshot.observation.focusedElementID ?? selectedElementID
        actionComposer.hydrate(from: snapshot)
    }

    func apply(health: HealthStatus) {
        self.health = health
        selectedControlPreset = health.controlPreset
    }

    func apply(recipe: RecipeDocument) {
        selectedRecipeName = recipe.name
        draftRecipe = recipe
        rawRecipeText = recipe.rawJSON ?? ""
        recipeRunParameters = recipe.params?.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = partialResult[entry.key] ?? ""
        } ?? [:]
    }

    func append(_ traceStep: TraceStepViewModel) {
        if traceSessions.contains(where: { $0.id == traceStep.sessionID }) {
            traceSessions = traceSessions.map {
                if $0.id == traceStep.sessionID {
                    return TraceSessionSummary(id: $0.id, stepCount: $0.stepCount + 1, lastUpdated: traceStep.timestamp)
                }
                return $0
            }.sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        } else {
            traceSessions.insert(
                TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp),
                at: 0
            )
        }

        if selectedTraceSessionID == traceStep.sessionID {
            if traceDetail == nil {
                let summary = TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp)
                traceDetail = TraceSessionDetail(summary: summary, steps: [traceStep])
            } else {
                let existingSteps = (traceDetail?.steps ?? []) + [traceStep]
                let summary = TraceSessionSummary(
                    id: traceStep.sessionID,
                    stepCount: existingSteps.count,
                    lastUpdated: traceStep.timestamp
                )
                traceDetail = TraceSessionDetail(summary: summary, steps: existingSteps)
            }
            selectedTraceStepID = traceStep.id
        }
    }

    func record(_ action: ActionRunResult) {
        currentActionResult = action

        if recentActions.contains(where: { $0.id == action.id }) {
            return
        }

        recentActions.insert(action, at: 0)
        if recentActions.count > 8 {
            recentActions = Array(recentActions.prefix(8))
        }
    }

    func replaceRecordedAction(_ action: ActionRunResult) {
        currentActionResult = action

        if let index = recentActions.firstIndex(where: { $0.id == action.id }) {
            recentActions[index] = action
            return
        }

        recentActions.insert(action, at: 0)
        if recentActions.count > 8 {
            recentActions = Array(recentActions.prefix(8))
        }
    }

    func markRejectedApproval(_ approval: ApprovalRequestDocument) {
        if let pendingAction = currentActionResult,
           pendingAction.isApprovalPending,
           pendingAction.approvalRequestID == approval.id {
            replaceRecordedAction(pendingAction.rejectedApprovalResult())
            inlineMessage = "Action approval was rejected."
        }

        if let latestRecipeRun,
           latestRecipeRun.pendingApprovalRequestID == approval.id {
            self.latestRecipeRun = latestRecipeRun.rejectedApprovalResult()
            inlineMessage = "Recipe approval was rejected."
        }
    }

    func syncSelectionAfterRecipeRefresh() {
        guard let selectedRecipeName else { return }
        if let refreshed = recipes.first(where: { $0.name == selectedRecipeName }) {
            if self.selectedRecipeName == draftRecipe.name {
                apply(recipe: refreshed)
            }
        } else {
            if self.selectedRecipeName == draftRecipe.name {
                createRecipe()
            } else {
                self.selectedRecipeName = nil
            }
        }
    }

    func validateDraftRecipe() -> String? {
        if recipeEditorMode == .raw {
            return nil
        }

        if draftRecipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe name is required."
        }
        if draftRecipe.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe description is required."
        }
        if draftRecipe.steps.isEmpty {
            return "At least one recipe step is required."
        }
        return nil
    }

    var currentMonitorApp: String? {
        monitorAppName.nilIfBlank
    }

    func requestForApprovedAction(from request: ActionRequest, approvalRequestID: String) -> ActionRequest {
        ActionRequest(
            kind: request.kind,
            appName: request.appName,
            windowTitle: request.windowTitle,
            query: request.query,
            role: request.role,
            domID: request.domID,
            text: request.text,
            clearExisting: request.clearExisting,
            x: request.x,
            y: request.y,
            button: request.button,
            count: request.count,
            key: request.key,
            modifiers: request.modifiers,
            direction: request.direction,
            amount: request.amount,
            waitCondition: request.waitCondition,
            waitValue: request.waitValue,
            timeout: request.timeout,
            interval: request.interval,
            approvalRequestID: approvalRequestID
        )
    }

    func resumeRecipeRun(resumeToken: String, approvalRequestID: String) async {
        do {
            let response = try await send(
                .init(
                    command: .resumeRecipeRun,
                    approvalRequestID: approvalRequestID,
                    resumeToken: resumeToken
                )
            )
            guard requireAcknowledged(response, fallback: "Recipe resume failed") else {
                return
            }
            if let recipeRun = response.recipeRun {
                recordRecipeRun(recipeRun, approvals: response.approvals)
                await loadTraceSessions()
                if let traceSessionID = recipeRun.traceSessionID {
                    await loadTraceSession(id: traceSessionID)
                }
                await loadDiagnostics()
            } else {
                errorMessage = response.errorMessage ?? "Recipe resume failed"
            }
        } catch {
            present(error)
        }
    }
}
