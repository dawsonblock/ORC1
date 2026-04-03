// ControllerStore+Operations.swift — Refresh, monitoring, approvals, trace, and IPC operations.

import AppKit
import Foundation
import OracleControllerShared

extension ControllerStore {
    func refreshNow() async {
        do {
            let response = try await send(.init(command: .refreshSnapshot, appName: currentMonitorApp))
            if let snapshot = response.snapshot {
                apply(snapshot: snapshot)
            }
            await refreshMissionControl()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHealth() async {
        do {
            let response = try await send(.init(command: .getHealth))
            if let health = response.health {
                self.health = health
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDiagnostics() async {
        do {
            let response = try await send(.init(command: .getDiagnostics))
            guard let diagnostics = response.diagnostics else { return }
            self.diagnostics = diagnostics
            selectedGraphEdgeID = selectedGraphEdgeID
                ?? diagnostics.graph.stableEdges.first?.id
                ?? diagnostics.graph.candidateEdges.first?.id
                ?? diagnostics.graph.recoveryEdges.first?.id
            selectedWorkflowID = selectedWorkflowID ?? diagnostics.workflows.first?.id
            selectedExperimentID = selectedExperimentID ?? diagnostics.experiments.first?.id
            selectedProjectMemoryID = selectedProjectMemoryID ?? diagnostics.projectMemory.first?.id
            selectedArchitectureFindingID = selectedArchitectureFindingID ?? diagnostics.architectureFindings.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMonitoring() async {
        do {
            _ = try await send(
                .init(
                    command: .setMonitoring,
                    monitoring: MonitoringConfiguration(
                        enabled: autoRefreshEnabled,
                        appName: currentMonitorApp,
                        intervalMs: 1000
                    )
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitAction() async {
        let request = actionComposer.makeRequest()
        await executeAction(request)
    }

    func loadApprovalRequests() async {
        do {
            let response = try await send(.init(command: .listApprovalRequests))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approveApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .approveApprovalRequest, approvalRequestID: approval.id))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
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
            errorMessage = error.localizedDescription
        }
    }

    func rejectApprovalRequest(_ approval: ApprovalRequestDocument) async {
        do {
            let response = try await send(.init(command: .rejectApprovalRequest, approvalRequestID: approval.id))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
            markRejectedApproval(approval)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSessions() async {
        do {
            let response = try await send(.init(command: .listTraceSessions))
            if let traceSessions = response.traceSessions {
                self.traceSessions = traceSessions
                if selectedTraceSessionID == nil {
                    selectedTraceSessionID = traceSessions.first?.id
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSession(id: String) async {
        do {
            let response = try await send(.init(command: .loadTraceSession, traceSessionID: id))
            guard let traceDetail = response.traceDetail else {
                errorMessage = response.errorMessage ?? "Trace not found"
                return
            }
            self.traceDetail = traceDetail
            self.selectedTraceSessionID = id
            self.selectedTraceStepID = traceDetail.steps.first?.id
            self.selectedSection = .traces
            await loadDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
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
            throw HostClientError.hostExited
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
                errorMessage = response.errorMessage ?? "Action failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
