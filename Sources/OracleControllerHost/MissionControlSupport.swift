import Foundation
import OracleControllerShared
import OracleOS

extension ControllerRuntimeBridge {
    func chatProviderStatus() -> ChatProviderStatus {
        ClaudeLocalCopilot.status()
    }

    func missionControlSnapshot(appName: String?) -> MissionControlSnapshot {
        let health = healthStatus()
        let diagnostics = diagnosticsSnapshot()
        let snapshot = refreshSnapshot(appName: appName)
        let approvals = listApprovalRequests()
        let traces = listTraceSessions()
        let recentSteps = Array(recordedSteps(since: 0).suffix(8))
        let metrics = container.metricsRecorder.current
        let providerStatus = chatProviderStatus()

        return MissionControlSnapshot(
            kpis: buildKPIs(
                health: health,
                diagnostics: diagnostics,
                approvals: approvals,
                metrics: metrics,
                providerStatus: providerStatus
            ),
            latencySeries: latencySeries(from: recentSteps),
            successSeries: successSeries(from: recentSteps),
            workflowSeries: workflowSeries(from: diagnostics.workflows),
            recentActivity: recentActivity(from: recentSteps),
            alerts: buildAlerts(
                health: health,
                diagnostics: diagnostics,
                approvals: approvals,
                recentSteps: recentSteps,
                traces: traces,
                providerStatus: providerStatus
            ),
            approvals: approvals,
            workflows: Array(diagnostics.workflows.prefix(4)),
            experiments: Array(diagnostics.experiments.prefix(3)),
            traceSessions: Array(traces.prefix(6)),
            repositoryIndexes: Array(diagnostics.repositoryIndexes.prefix(3)),
            health: health,
            snapshot: snapshot,
            host: diagnostics.host,
            browser: diagnostics.browser,
            providerStatus: providerStatus,
            recommendedPrompts: recommendedPrompts(
                health: health,
                approvals: approvals,
                recentSteps: recentSteps,
                traces: traces,
                providerStatus: providerStatus
            )
        )
    }

    private func buildKPIs(
        health: HealthStatus,
        diagnostics: ControllerDiagnosticsSnapshot,
        approvals: [ApprovalRequestDocument],
        metrics: RuntimeMetrics,
        providerStatus: ChatProviderStatus
    ) -> [DashboardKPI] {
        let missingPermissions = health.permissions.filter { !$0.granted }
        let storageIssues = health.storageLocations.filter { !$0.writable }
        let readinessValue = missingPermissions.isEmpty && health.controllerConnected && storageIssues.isEmpty ? "Ready" : "Attention"
        let readinessTone: DashboardTone = readinessValue == "Ready" ? .good : .warning
        let successRate = diagnostics.graph.globalSuccessRate > 0 ? diagnostics.graph.globalSuccessRate : metrics.actionSuccessRate
        let avgLatency = averageLatency(from: diagnostics, metrics: metrics)
        let stableWorkflowCount = diagnostics.workflows.filter { $0.promotionStatus.lowercased().contains("promot") || $0.promotionStatus.lowercased().contains("stable") }.count
        let readinessDetail: String

        if !storageIssues.isEmpty {
            readinessDetail = "\(storageIssues.count) local data path issue(s) need attention"
        } else {
            readinessDetail = "\(health.permissions.count - missingPermissions.count)/\(health.permissions.count) permissions granted"
        }

        return [
            DashboardKPI(
                id: "runtime-readiness",
                title: "Runtime readiness",
                value: readinessValue,
                detail: readinessDetail,
                tone: readinessTone
            ),
            DashboardKPI(
                id: "runtime-control",
                title: "Runtime control",
                value: health.controlPreset.title,
                detail: "\(health.controlPreset.summary) Live mode: \(health.policyMode).",
                tone: runtimeControlTone(for: health.controlPreset)
            ),
            DashboardKPI(
                id: "verified-success",
                title: "Verified success",
                value: percentage(successRate),
                detail: "Graph-backed success across trusted execution history",
                tone: successRate >= 0.75 ? .good : (successRate >= 0.4 ? .warning : .danger)
            ),
            DashboardKPI(
                id: "avg-latency",
                title: "Average latency",
                value: avgLatency > 0 ? "\(Int(avgLatency)) ms" : "No data",
                detail: "Mean verified step latency",
                tone: avgLatency == 0 ? .neutral : (avgLatency < 1200 ? .good : .warning)
            ),
            DashboardKPI(
                id: "approvals",
                title: "Pending approvals",
                value: "\(approvals.count)",
                detail: approvals.isEmpty ? "No risky actions are blocked" : "Risk-gated actions are waiting for review",
                tone: approvals.isEmpty ? .good : .warning
            ),
            DashboardKPI(
                id: "workflow-reuse",
                title: "Workflow reuse",
                value: "\(stableWorkflowCount)",
                detail: "\(diagnostics.workflows.count) learned workflows detected",
                tone: stableWorkflowCount > 0 ? .good : .neutral
            ),
            DashboardKPI(
                id: "copilot",
                title: "Copilot provider",
                value: copilotValue(for: providerStatus),
                detail: copilotDetail(for: providerStatus),
                tone: copilotTone(for: providerStatus)
            ),
        ]
    }

    private func averageLatency(from diagnostics: ControllerDiagnosticsSnapshot, metrics: RuntimeMetrics) -> Double {
        let edges = diagnostics.graph.stableEdges + diagnostics.graph.candidateEdges + diagnostics.graph.recoveryEdges
        let latencies = edges.map(\.averageLatencyMs).filter { $0 > 0 }
        if !latencies.isEmpty {
            return latencies.reduce(0, +) / Double(latencies.count)
        }
        return metrics.meanTimePerAction
    }

    private func latencySeries(from steps: [TraceStepViewModel]) -> DashboardSeries {
        DashboardSeries(
            id: "latency",
            title: "Latency",
            subtitle: "Recent verified steps",
            tone: .neutral,
            points: steps.map {
                DashboardSeriesPoint(
                    id: $0.id,
                    label: shortLabel(for: $0.timestamp),
                    value: $0.elapsedMs,
                    detail: $0.actionName
                )
            }
        )
    }

    private func successSeries(from steps: [TraceStepViewModel]) -> DashboardSeries {
        DashboardSeries(
            id: "success",
            title: "Verification",
            subtitle: "Recent step outcomes",
            tone: .good,
            points: steps.map {
                DashboardSeriesPoint(
                    id: "success-\($0.id)",
                    label: shortLabel(for: $0.timestamp),
                    value: $0.success ? 100 : 0,
                    detail: $0.success ? "Verified" : ($0.failureClass ?? "Failed")
                )
            }
        )
    }

    private func workflowSeries(from workflows: [ControllerWorkflowDiagnostics]) -> DashboardSeries {
        DashboardSeries(
            id: "workflow",
            title: "Workflow reuse",
            subtitle: "Top reusable workflow success rates",
            tone: .good,
            points: workflows.prefix(5).map {
                DashboardSeriesPoint(
                    id: $0.id,
                    label: compactWorkflowLabel($0.goalPattern),
                    value: $0.successRate * 100,
                    detail: $0.promotionStatus
                )
            }
        )
    }

    private func recentActivity(from steps: [TraceStepViewModel]) -> [MissionActivityEntry] {
        steps.reversed().map {
            MissionActivityEntry(
                id: $0.id,
                title: $0.actionName.capitalized + ($0.actionTarget.map { " \($0)" } ?? ""),
                subtitle: $0.success ? ($0.notes ?? "Verified execution recorded") : ($0.failureClass ?? "Execution failed"),
                timestamp: $0.timestamp,
                tone: $0.success ? .good : .danger,
                traceSessionID: $0.sessionID,
                traceStepID: $0.stepID
            )
        }
    }

    private func buildAlerts(
        health: HealthStatus,
        diagnostics: ControllerDiagnosticsSnapshot,
        approvals: [ApprovalRequestDocument],
        recentSteps: [TraceStepViewModel],
        traces: [TraceSessionSummary],
        providerStatus: ChatProviderStatus
    ) -> [AlertSummary] {
        var alerts: [AlertSummary] = []
        let storageIssues = health.storageLocations.filter { !$0.writable }

        for permission in health.permissions where !permission.granted {
            alerts.append(
                AlertSummary(
                    id: permission.id,
                    title: "\(permission.title) required",
                    message: permission.detail ?? "Grant access in System Settings to unlock the full controller.",
                    severity: .critical,
                    source: "health"
                )
            )
        }

        if !storageIssues.isEmpty {
            alerts.append(
                AlertSummary(
                    id: "storage-paths",
                    title: "Local storage needs attention",
                    message: "Fix write access for \(storageIssues.map(\.title).joined(separator: ", ")) before relying on recipes, approvals, traces, or graph persistence.",
                    severity: .warning,
                    source: "storage"
                )
            )
        }

        if !approvals.isEmpty {
            alerts.append(
                AlertSummary(
                    id: "approvals-pending",
                    title: "\(approvals.count) approvals pending in \(health.controlPreset.title)",
                    message: approvalSummary(for: approvals, health: health),
                    severity: .warning,
                    source: "approvals"
                )
            )
        }

        if let blockedStep = recentSteps.reversed().first(where: { $0.blockedByPolicy }) {
            alerts.append(
                AlertSummary(
                    id: "policy-blocked-\(blockedStep.id)",
                    title: "\(health.controlPreset.title) blocked a recent action",
                    message: blockedActionSummary(for: blockedStep, health: health),
                    severity: .warning,
                    source: "policy"
                )
            )
        }

        if providerStatus.configured && providerStatus.state != .ready {
            alerts.append(
                AlertSummary(
                    id: "copilot-status",
                    title: "Copilot unavailable",
                    message: providerStatus.detail,
                    severity: .warning,
                    source: "copilot"
                )
            )
        }

        if !health.visionSidecarRunning {
            alerts.append(
                AlertSummary(
                    id: "vision-sidecar",
                    title: "Vision sidecar offline",
                    message: "AX-first control is still available, but vision-assisted workflows are degraded.",
                    severity: .info,
                    source: "vision"
                )
            )
        }

        if traces.isEmpty {
            alerts.append(
                AlertSummary(
                    id: "no-traces",
                    title: "No trace history yet",
                    message: "Run a manual action or recipe to populate execution history and charts.",
                    severity: .info,
                    source: "traces"
                )
            )
        }

        if diagnostics.graph.promotionsFrozen {
            alerts.append(
                AlertSummary(
                    id: "promotions-frozen",
                    title: "Knowledge promotion frozen",
                    message: "Stable graph promotion is frozen until additional trusted evidence is recorded.",
                    severity: .warning,
                    source: "diagnostics"
                )
            )
        }

        return Array(alerts.prefix(6))
    }

    private func recommendedPrompts(
        health: HealthStatus,
        approvals: [ApprovalRequestDocument],
        recentSteps: [TraceStepViewModel],
        traces: [TraceSessionSummary],
        providerStatus: ChatProviderStatus
    ) -> [String] {
        var prompts: [String] = []

        if health.permissions.contains(where: { !$0.granted }) {
            prompts.append("What permissions are missing, and what should I fix first?")
        }

        if health.storageLocations.contains(where: { !$0.writable }) {
            prompts.append("Which local data paths are not writable, and how do I fix them?")
        }

        if !approvals.isEmpty {
            prompts.append("Why is \(health.controlPreset.title) reviewing these risky actions right now?")
        }

        if let blockedStep = recentSteps.reversed().first(where: { $0.blockedByPolicy }) {
            prompts.append("Why did \(health.controlPreset.title) block \(actionLabel(for: blockedStep))?")
        }

        if !traces.isEmpty {
            prompts.append("What do the latest traces say about runtime reliability?")
        }

        if providerStatus.available && !providerStatus.configured {
            prompts.append("How do I finish copilot setup for Oracle Controller?")
        }

        prompts.append("What should I do next to improve system readiness?")
        return Array(prompts.prefix(4))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func shortLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func compactWorkflowLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 18 else { return trimmed }
        return String(trimmed.prefix(18)) + "…"
    }

    private func copilotValue(for status: ChatProviderStatus) -> String {
        switch status.state {
        case .ready:
            return "Ready"
        case .setupRequired:
            return "Optional"
        case .unavailable:
            return status.configured ? "Unavailable" : "Optional"
        }
    }

    private func copilotDetail(for status: ChatProviderStatus) -> String {
        switch status.state {
        case .ready:
            return status.displayName
        case .setupRequired where !status.configured:
            return "Optional local advisory assistant."
        case .setupRequired, .unavailable:
            return status.detail
        }
    }

    private func copilotTone(for status: ChatProviderStatus) -> DashboardTone {
        switch status.state {
        case .ready:
            return .good
        case .setupRequired:
            return .neutral
        case .unavailable:
            return status.configured ? .warning : .neutral
        }
    }

    private func runtimeControlTone(for preset: RuntimeControlPreset) -> DashboardTone {
        switch preset {
        case .fullControl:
            return .warning
        case .original:
            return .good
        case .less:
            return .warning
        case .aiDecides:
            return .neutral
        }
    }

    private func approvalSummary(for approvals: [ApprovalRequestDocument], health: HealthStatus) -> String {
        guard let firstApproval = approvals.first else {
            return "No risky actions are waiting for review."
        }

        let remainder = approvals.count > 1 ? " \(approvals.count - 1) more action(s) are waiting behind it." : ""
        return "\(health.controlPreset.title) is reviewing \(firstApproval.displayTitle) because \(lowercasedLeadingSentence(firstApproval.reason)).\(remainder)"
    }

    private func blockedActionSummary(for step: TraceStepViewModel, health: HealthStatus) -> String {
        let action = actionLabel(for: step)

        if let protectedOperation = step.protectedOperation {
            return "\(health.controlPreset.title) blocked \(action) because \(blockedOperationExplanation(for: protectedOperation, preset: health.controlPreset))."
        }

        return "\(health.controlPreset.title) blocked \(action) because the current policy mode does not allow that action to continue."
    }

    private func actionLabel(for step: TraceStepViewModel) -> String {
        if let target = step.actionTarget, !target.isEmpty {
            return "\(step.actionName.capitalized) \(target)"
        }
        return step.actionName.capitalized
    }

    private func blockedOperationExplanation(for protectedOperation: String, preset: RuntimeControlPreset) -> String {
        switch preset {
        case .fullControl, .original:
            return "the runtime still keeps hard safety blocks on \(protectedOperation.replacingOccurrences(of: "-", with: " ")) operations"
        case .less:
            return "this stricter mode blocks risky operations instead of pausing them for approval"
        case .aiDecides:
            switch protectedOperation {
            case "send", "purchase", "delete", "upload-share", "external-network-fetch", "git-push", "destructive-vcs":
                return "this adaptive mode blocks irreversible or external risky actions outright"
            default:
                return "the runtime still keeps hard safety blocks on protected operations"
            }
        }
    }

    private func lowercasedLeadingSentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return trimmed
        }
        return first.lowercased() + trimmed.dropFirst()
    }
}
