// ControllerStore+Operations.swift — Refresh, monitoring, approvals, trace, and IPC operations.

import AppKit
import Foundation
import OracleControllerShared

extension ControllerStore {
    func refreshNow() async {
        do {
            let response = try await send(.init(command: .refreshSnapshot, appName: currentMonitorApp))
            applySnapshotResponse(response)
            await refreshMissionControl()
        } catch {
            present(error)
        }
    }

    func refreshHealth() async {
        do {
            let response = try await send(.init(command: .getHealth))
            applyHealthResponse(response)
        } catch {
            present(error)
        }
    }

    func setControlPreset(_ preset: RuntimeControlPreset) async {
        let previousPreset = selectedControlPreset
        selectedControlPreset = preset
        isUpdatingControlPreset = true

        defer {
            isUpdatingControlPreset = false
        }

        do {
            let response = try await send(.init(command: .setControlPreset, controlPreset: preset))
            guard requireAcknowledged(response, fallback: "Runtime control update failed") else {
                selectedControlPreset = previousPreset
                return
            }

            applyHealthResponse(response, fallback: "Runtime control update did not return health state")
        } catch {
            selectedControlPreset = previousPreset
            present(error)
        }
    }

    func loadDiagnostics() async {
        do {
            let response = try await send(.init(command: .getDiagnostics))
            applyDiagnosticsResponse(response)
        } catch {
            present(error)
        }
    }

    func updateMonitoring(previousValue: Bool? = nil) async {
        do {
            let response = try await send(
                .init(
                    command: .setMonitoring,
                    monitoring: MonitoringConfiguration(
                        enabled: autoRefreshEnabled,
                        appName: currentMonitorApp,
                        intervalMs: 1000
                    )
                )
            )
            guard requireAcknowledged(response, fallback: "Monitoring update failed") else {
                if let previousValue {
                    autoRefreshEnabled = previousValue
                }
                return
            }
        } catch {
            if let previousValue {
                autoRefreshEnabled = previousValue
            }
            present(error)
        }
    }

    func retryHostConnection() async {
        do {
            isBusy = true
            errorMessage = nil
            defer { isBusy = false }

            try await bootstrapHost()
            await refreshHealth()
            await loadDiagnostics()
            await refreshMissionControl()
            isLoaded = true
        } catch {
            present(error)
        }
    }

    func submitAction() async {
        let request = actionComposer.makeRequest()
        await executeAction(request)
    }

    func loadApprovalRequests() async {
        do {
            let response = try await send(.init(command: .listApprovalRequests))
            applyApprovalsResponse(response)
        } catch {
            present(error)
        }
    }

    func approveApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .approveApprovalRequest, approvalRequestID: approval.id))
            guard requireAcknowledged(response, fallback: "Approval request could not be approved") else {
                return
            }
            applyApprovalsResponse(response, fallback: "Approval state unavailable after approval")
            if let pendingAction = currentActionResult,
               pendingAction.approvalStatus == "pending",
               pendingAction.approvalRequestID == approval.id
            {
                await executeAction(requestForApprovedAction(from: pendingAction.request, approvalRequestID: approval.id))
                return
            }
            if latestRecipeRun?.paused == true,
               latestRecipeRun?.pendingApprovalRequestID == approval.id,
               let resumeToken = latestRecipeRun?.resumeToken
            {
                await resumeRecipeRun(resumeToken: resumeToken, approvalRequestID: approval.id)
            }
        } catch {
            present(error)
        }
    }

    func rejectApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .rejectApprovalRequest, approvalRequestID: approval.id))
            guard requireAcknowledged(response, fallback: "Approval request could not be rejected") else {
                return
            }
            applyApprovalsResponse(response, fallback: "Approval state unavailable after rejection")
            markRejectedApproval(approval)
        } catch {
            present(error)
        }
    }

    func loadTraceSessions() async {
        do {
            let response = try await send(.init(command: .listTraceSessions))
            applyTraceSessionsResponse(response)
        } catch {
            present(error)
        }
    }

    func loadTraceSession(id: String) async {
        do {
            let response = try await send(.init(command: .loadTraceSession, traceSessionID: id))
            guard applyTraceDetailResponse(response, requestedID: id) else {
                return
            }
            await loadDiagnostics()
        } catch {
            present(error)
        }
    }

    func openArtifact(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealArtifact(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func send(_ request: ControllerHostRequest) async throws -> ControllerHostResponse {
        guard let hostClient else {
            throw HostClientError.hostExited(status: nil)
        }
        return try await hostClient.send(request)
    }

    func executeAction(_ request: ActionRequest) async {
        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .performAction, action: request))
            if let result = response.actionResult {
                record(result)
                if let resultingObservation = result.resultingObservation {
                    snapshot = ControlSnapshot(
                        capturedAt: Date(),
                        observation: resultingObservation,
                        screenshot: snapshot?.screenshot
                    )
                    selectedElementID = resultingObservation.focusedElementID
                }
                inlineMessage = result.summaryText
                if let approvals = response.approvals {
                    approvalQueue = approvals
                }
                if let missionControl = response.missionControl {
                    self.missionControl = missionControl
                }
            } else {
                currentActionResult = nil
                errorMessage = response.errorMessage ?? "Action failed"
            }
        } catch {
            present(error)
        }
    }
}
