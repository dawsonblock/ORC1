// ControllerStore+Internal.swift — Internal helpers: event handling, state application, and run bookkeeping.

import Foundation
import OracleControllerShared

extension ControllerStore {
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
                self.health = health
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

    func applyBootstrap(_ bootstrap: DashboardBootstrap?) {
        guard let bootstrap else { return }
        session = bootstrap.session
        snapshot = bootstrap.snapshot
        health = bootstrap.health
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
            self.selectedRecipeName = nil
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
            if let recipeRun = response.recipeRun {
                latestRecipeRun = recipeRun
                inlineMessage = recipeRun.summaryText
            }
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
