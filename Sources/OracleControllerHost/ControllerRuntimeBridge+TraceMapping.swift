// ControllerRuntimeBridge+TraceMapping.swift — Trace event model mapping helper.

import Foundation
import OracleControllerShared
import OracleOS

extension ControllerRuntimeBridge {
    func map(_ event: TraceEvent) -> TraceStepViewModel {
        let notePaths = event.notes?
            .split(separator: "|")
            .compactMap { segment -> String? in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = trimmed.firstIndex(of: "=") {
                    return String(trimmed[trimmed.index(after: index)...])
                }
                return trimmed.hasPrefix("/") ? trimmed : nil
            } ?? []

        let artifactPaths = Array(Set(([event.screenshotPath].compactMap { $0 } + notePaths))).sorted()

        return TraceStepViewModel(
            sessionID: event.sessionID,
            stepID: event.stepID,
            timestamp: event.timestamp,
            toolName: event.toolName,
            actionName: event.actionName,
            actionTarget: event.actionTarget,
            actionText: event.actionText,
            selectedElementID: event.selectedElementID,
            selectedElementLabel: event.selectedElementLabel,
            candidateScore: event.candidateScore,
            candidateReasons: event.candidateReasons,
            preObservationHash: event.preObservationHash,
            postObservationHash: event.postObservationHash,
            postcondition: event.postcondition,
            verified: event.verified,
            success: event.success,
            failureClass: event.failureClass,
            surface: event.surface,
            policyMode: event.policyMode,
            protectedOperation: event.protectedOperation,
            approvalRequestID: event.approvalRequestID,
            approvalOutcome: event.approvalOutcome,
            blockedByPolicy: event.blockedByPolicy ?? false,
            appProfile: event.appProfile,
            agentKind: event.agentKind,
            domain: event.domain,
            plannerFamily: event.plannerFamily,
            workspaceRelativePath: event.workspaceRelativePath,
            commandCategory: event.commandCategory,
            commandSummary: event.commandSummary,
            repositorySnapshotID: event.repositorySnapshotID,
            buildResultSummary: event.buildResultSummary,
            testResultSummary: event.testResultSummary,
            patchID: event.patchID,
            projectMemoryRefs: event.projectMemoryRefs ?? [],
            experimentID: event.experimentID,
            candidateID: event.candidateID,
            sandboxPath: event.sandboxPath,
            experimentExecutionContext: event.experimentID == nil ? nil : ExperimentExecutionContext.sandbox.rawValue,
            experimentCommittedToWorkspace: event.experimentID == nil ? nil : false,
            selectedCandidate: event.selectedCandidate,
            experimentOutcome: event.experimentOutcome,
            architectureFindings: event.architectureFindings ?? [],
            refactorProposalID: event.refactorProposalID,
            knowledgeTier: event.knowledgeTier,
            elapsedMs: event.elapsedMs,
            screenshotPath: event.screenshotPath,
            artifactPaths: artifactPaths,
            notes: event.notes
        )
    }
}
