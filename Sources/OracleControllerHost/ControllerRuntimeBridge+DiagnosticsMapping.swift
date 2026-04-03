// ControllerRuntimeBridge+DiagnosticsMapping.swift — Diagnostics model mapping helpers.

import Foundation
import OracleControllerShared
import OracleOS

extension ControllerRuntimeBridge {
    func map(_ snapshot: RuntimeDiagnosticsSnapshot) -> ControllerDiagnosticsSnapshot {
        ControllerDiagnosticsSnapshot(
            generatedAt: snapshot.generatedAt,
            graph: ControllerGraphDiagnostics(
                stableEdges: snapshot.graph.stableEdges.map(map),
                candidateEdges: snapshot.graph.candidateEdges.map(map),
                recoveryEdges: snapshot.graph.recoveryEdges.map(map),
                promotionEligibleCount: snapshot.graph.promotionEligibleCount,
                promotionsFrozen: snapshot.graph.promotionsFrozen,
                globalSuccessRate: snapshot.graph.globalSuccessRate
            ),
            workflows: snapshot.workflows.map(map),
            experiments: snapshot.experiments.map(map),
            recovery: ControllerRecoveryDiagnostics(
                recoveryStepCount: snapshot.recovery.recoveryStepCount,
                strategies: snapshot.recovery.strategies.map(map)
            ),
            projectMemory: snapshot.projectMemory.map(map),
            architectureFindings: snapshot.architectureFindings.map(map),
            repositoryIndexes: snapshot.repositoryIndexes.map(map),
            host: snapshot.host.map(map),
            browser: snapshot.browser.map(map)
        )
    }

    func map(_ edge: DiagnosticsGraphEdge) -> ControllerGraphEdgeDiagnostics {
        ControllerGraphEdgeDiagnostics(
            id: edge.id,
            actionContractID: edge.actionContractID,
            fromPlanningStateID: edge.fromPlanningStateID,
            toPlanningStateID: edge.toPlanningStateID,
            agentKind: edge.agentKind,
            domain: edge.domain,
            workspaceRelativePath: edge.workspaceRelativePath,
            commandCategory: edge.commandCategory,
            plannerFamily: edge.plannerFamily,
            knowledgeTier: edge.knowledgeTier,
            attempts: edge.attempts,
            successRate: edge.successRate,
            averageLatencyMs: edge.averageLatencyMs,
            targetAmbiguityRate: edge.targetAmbiguityRate,
            rollingSuccessRate: edge.rollingSuccessRate,
            recoveryTagged: edge.recoveryTagged,
            approvalRequired: edge.approvalRequired,
            approvalOutcome: edge.approvalOutcome,
            lastSuccessAt: edge.lastSuccessAt,
            lastAttemptAt: edge.lastAttemptAt,
            failureHistogram: edge.failureHistogram,
            promotionEligible: edge.promotionEligible
        )
    }

    func map(_ workflow: DiagnosticsWorkflowSummary) -> ControllerWorkflowDiagnostics {
        ControllerWorkflowDiagnostics(
            id: workflow.id,
            goalPattern: workflow.goalPattern,
            agentKind: workflow.agentKind,
            promotionStatus: workflow.promotionStatus,
            successRate: workflow.successRate,
            replayValidationSuccess: workflow.replayValidationSuccess,
            repeatedTraceSegmentCount: workflow.repeatedTraceSegmentCount,
            stepCount: workflow.stepCount,
            parameterSlots: workflow.parameterSlots,
            sourceTraceRefs: workflow.sourceTraceRefs,
            sourceGraphEdgeRefs: workflow.sourceGraphEdgeRefs,
            stale: workflow.stale
        )
    }

    func map(_ experiment: DiagnosticsExperimentSummary) -> ControllerExperimentDiagnostics {
        ControllerExperimentDiagnostics(
            id: experiment.id,
            candidateCount: experiment.candidateCount,
            selectedCandidateID: experiment.selectedCandidateID,
            winningSandboxPath: experiment.winningSandboxPath,
            succeededCandidateCount: experiment.succeededCandidateCount,
            candidates: experiment.candidates.map(map)
        )
    }

    func map(_ candidate: DiagnosticsExperimentCandidate) -> ControllerExperimentCandidateDiagnostics {
        ControllerExperimentCandidateDiagnostics(
            id: candidate.id,
            title: candidate.title,
            summary: candidate.summary,
            workspaceRelativePath: candidate.workspaceRelativePath,
            hypothesis: candidate.hypothesis,
            selected: candidate.selected,
            succeeded: candidate.succeeded,
            architectureRiskScore: candidate.architectureRiskScore,
            sandboxPath: candidate.sandboxPath,
            diffSummary: candidate.diffSummary,
            buildSummary: candidate.buildSummary,
            testSummary: candidate.testSummary,
            architectureFindings: candidate.architectureFindings
        )
    }

    func map(_ strategy: DiagnosticsRecoveryStrategy) -> ControllerRecoveryStrategyDiagnostics {
        ControllerRecoveryStrategyDiagnostics(
            id: strategy.id,
            attempts: strategy.attempts,
            successes: strategy.successes,
            failures: strategy.failures,
            failureHistogram: strategy.failureHistogram
        )
    }

    func map(_ record: DiagnosticsProjectMemoryRecord) -> ControllerProjectMemoryDiagnostics {
        ControllerProjectMemoryDiagnostics(
            id: record.id,
            title: record.title,
            summary: record.summary,
            kind: record.kind,
            knowledgeClass: record.knowledgeClass,
            status: record.status,
            path: record.path,
            affectedModules: record.affectedModules,
            evidenceRefs: record.evidenceRefs
        )
    }

    func map(_ finding: DiagnosticsArchitectureFinding) -> ControllerArchitectureFindingDiagnostics {
        ControllerArchitectureFindingDiagnostics(
            id: finding.id,
            title: finding.title,
            summary: finding.summary,
            severity: finding.severity,
            affectedModules: finding.affectedModules,
            evidence: finding.evidence,
            riskScore: finding.riskScore,
            occurrences: finding.occurrences,
            governanceRuleID: finding.governanceRuleID
        )
    }

    func map(_ index: DiagnosticsRepositoryIndex) -> ControllerRepositoryIndexDiagnostics {
        ControllerRepositoryIndexDiagnostics(
            id: index.id,
            workspaceRoot: index.workspaceRoot,
            buildTool: index.buildTool,
            activeBranch: index.activeBranch,
            isGitDirty: index.isGitDirty,
            indexedAt: index.indexedAt,
            fileCount: index.fileCount,
            symbolCount: index.symbolCount,
            dependencyCount: index.dependencyCount,
            callEdgeCount: index.callEdgeCount,
            testEdgeCount: index.testEdgeCount,
            buildTargetCount: index.buildTargetCount,
            topSymbols: index.topSymbols,
            buildTargets: index.buildTargets,
            topTests: index.topTests
        )
    }

    func map(_ host: DiagnosticsHostSnapshot) -> ControllerHostDiagnostics {
        ControllerHostDiagnostics(
            snapshotID: host.snapshotID,
            activeApplication: host.activeApplication,
            accessibilityGranted: host.accessibilityGranted,
            screenRecordingGranted: host.screenRecordingGranted,
            windowCount: host.windowCount,
            menuCount: host.menuCount,
            dialogTitle: host.dialogTitle,
            capturedWindowTitle: host.capturedWindowTitle,
            windows: host.windows.map(map)
        )
    }

    func map(_ window: DiagnosticsHostWindow) -> ControllerHostWindowDiagnostics {
        ControllerHostWindowDiagnostics(
            id: window.id,
            appName: window.appName,
            title: window.title,
            elementCount: window.elementCount,
            focused: window.focused
        )
    }

    func map(_ browser: DiagnosticsBrowserSnapshot) -> ControllerBrowserDiagnostics {
        ControllerBrowserDiagnostics(
            appName: browser.appName,
            available: browser.available,
            url: browser.url,
            title: browser.title,
            domain: browser.domain,
            indexedElementCount: browser.indexedElementCount,
            topIndexedLabels: browser.topIndexedLabels,
            simplifiedTextPreview: browser.simplifiedTextPreview
        )
    }
}
