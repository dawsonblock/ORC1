import Charts
import SwiftUI
import OracleControllerShared

struct ControllerStatusBar: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(spacing: 12) {
            statusChip("Host", store.hostConnection.label, tone: hostTone)
            statusChip("Runtime", runtimeValue, tone: runtimeTone)
            statusChip("Control", controlValue, tone: controlTone)
            statusChip("Monitor", store.autoRefreshEnabled ? "Active" : "Paused", tone: store.autoRefreshEnabled ? .neutral : .warning)
            statusChip("Copilot", copilotValue, tone: copilotTone)
            Spacer()
            if let generatedAt = store.missionControl?.generatedAt {
                Text("Updated \(generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ControllerTheme.panelRaised.opacity(0.9), ControllerTheme.panelTint.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ControllerTheme.borderStrong.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: ControllerTheme.shadow, radius: 16, y: 8)
        )
    }

    private var runtimeValue: String {
        if store.hostConnection.phase == .launching {
            return "Launching"
        }
        if store.hostConnection.requiresAttention {
            return "Unavailable"
        }
        guard let health = store.health else { return "Loading" }
        if !health.controllerConnected {
            return "Disconnected"
        }
        if health.storageLocations.contains(where: { !$0.writable }) {
            return "Attention"
        }
        return health.permissions.allSatisfy { $0.granted } ? "Connected" : "Attention"
    }

    private var runtimeTone: StatusBadge.Tone {
        if store.hostConnection.phase == .launching {
            return .neutral
        }
        if store.hostConnection.phase == .failed {
            return .danger
        }
        if store.hostConnection.phase == .disconnected {
            return .warning
        }
        guard let health = store.health else { return .neutral }
        if !health.controllerConnected {
            return .warning
        }
        if health.storageLocations.contains(where: { !$0.writable }) {
            return .warning
        }
        return health.permissions.allSatisfy { $0.granted } ? .good : .warning
    }

    private var hostTone: StatusBadge.Tone {
        switch store.hostConnection.phase {
        case .connected:
            return .good
        case .launching, .idle:
            return .neutral
        case .disconnected:
            return .warning
        case .failed:
            return .danger
        }
    }

    private var copilotValue: String {
        guard let status = store.chatProviderStatus else { return "Optional" }
        switch status.state {
        case .ready:
            return "Ready"
        case .setupRequired:
            return "Optional"
        case .unavailable:
            return status.configured ? "Unavailable" : "Optional"
        }
    }

    private var copilotTone: StatusBadge.Tone {
        guard let status = store.chatProviderStatus else { return .neutral }
        switch status.state {
        case .ready:
            return .good
        case .setupRequired:
            return .neutral
        case .unavailable:
            return status.configured ? .warning : .neutral
        }
    }

    private var controlValue: String {
        store.missionControl?.health.controlPreset.title
            ?? store.health?.controlPreset.title
            ?? store.selectedControlPreset?.title
            ?? "Loading"
    }

    private var controlTone: StatusBadge.Tone {
        let preset = store.missionControl?.health.controlPreset
            ?? store.health?.controlPreset
            ?? store.selectedControlPreset

        switch preset {
        case .fullControl:
            return .warning
        case .original:
            return .good
        case .less:
            return .warning
        case .aiDecides:
            return .neutral
        case nil:
            return .neutral
        }
    }

    private func statusChip(_ title: String, _ value: String, tone: StatusBadge.Tone) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            StatusBadge(label: value, tone: tone)
        }
    }
}

struct MissionControlWorkspaceView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                if let missionControl = store.missionControl {
                    MissionBriefingCard(store: store, missionControl: missionControl)

                    KPIGrid(kpis: missionControl.kpis)

                    HStack(alignment: .top, spacing: layout.stackSpacing) {
                        PanelCard("Live Monitor", subtitle: missionControl.snapshot?.observation.windowTitle ?? "Current observation snapshot") {
                            ScreenshotPreview(screenshot: missionControl.snapshot?.screenshot ?? store.snapshot?.screenshot)
                                .frame(maxWidth: .infinity, minHeight: 340)
                        }
                        .frame(maxWidth: .infinity)

                        MissionAlertsCard(missionControl: missionControl)
                            .frame(width: layout.railPanelWidth)
                    }

                    HStack(alignment: .top, spacing: layout.stackSpacing) {
                        DashboardSeriesCard(series: missionControl.latencySeries, mode: .line)
                        DashboardSeriesCard(series: missionControl.successSeries, mode: .bar)
                        DashboardSeriesCard(series: missionControl.workflowSeries, mode: .bar)
                    }

                    HStack(alignment: .top, spacing: layout.stackSpacing) {
                        ActivityTimelineCard(entries: missionControl.recentActivity)
                            .frame(maxWidth: .infinity)
                        WorkflowExperimentCard(workflows: missionControl.workflows, experiments: missionControl.experiments)
                            .frame(width: layout.utilityPanelWidth)
                    }
                } else {
                    PanelCard("Mission Control", subtitle: "Loading live controller state") {
                        EmptyStateView(
                            systemImage: "gauge.with.dots.needle.67percent",
                            title: "Mission Control is empty",
                            message: "Refresh the controller to load runtime health, diagnostics, traces, and copilot readiness."
                        )
                        .frame(height: 360)

                        Button("Refresh Mission Control") {
                            Task { await store.refreshMissionControl() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(layout.workspacePaddingValue)
        }
    }
}

struct MissionControlInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Mission Control Summary", subtitle: "Current operator posture and copilot guidance") {
            if let missionControl = store.missionControl {
                KVRow(key: "Provider", value: missionControl.providerStatus.displayName)
                KVRow(key: "Provider state", value: missionControl.providerStatus.state.rawValue)
                KVRow(key: "Runtime control", value: missionControl.health.controlPreset.title)
                KVRow(key: "Policy mode", value: missionControl.health.policyMode)
                KVRow(key: "Alerts", value: "\(missionControl.alerts.count)")
                KVRow(key: "Approvals", value: "\(missionControl.approvals.count)")
                KVRow(key: "Trace sessions", value: "\(missionControl.traceSessions.count)")

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended prompts")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    ForEach(missionControl.recommendedPrompts, id: \.self) { prompt in
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                EmptyStateView(
                    systemImage: "sparkle.magnifyingglass",
                    title: "No mission snapshot",
                    message: "Refresh Mission Control to populate the dashboard summary."
                )
                .frame(height: 220)
            }
        }
        .padding(16)
    }
}

private struct KPIGrid: View {
    let kpis: [DashboardKPI]
    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(kpis) { kpi in
                MetricTile(
                    label: kpi.title,
                    value: kpi.value,
                    detail: kpi.detail,
                    tone: tone(for: kpi.tone)
                )
            }
        }
    }

    private func tone(for tone: DashboardTone) -> StatusBadge.Tone {
        switch tone {
        case .neutral: return .neutral
        case .good: return .good
        case .warning: return .warning
        case .danger: return .danger
        }
    }
}

private struct MissionBriefingCard: View {
    @Bindable var store: ControllerStore
    let missionControl: MissionControlSnapshot

    var body: some View {
        PanelCard("Mission Briefing", subtitle: "Immediate operator posture and best next step", style: .hero) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(ControllerTheme.ink)
                    Text(summary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    StatusBadge(label: readinessLabel, tone: readinessTone)
                    Text("Updated \(missionControl.generatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                MetricTile(
                    label: "Focused App",
                    value: missionControl.snapshot?.observation.appName ?? "None",
                    detail: missionControl.snapshot?.observation.windowTitle ?? "No active window",
                    tone: .neutral
                )
                MetricTile(
                    label: "Approvals",
                    value: "\(missionControl.approvals.count)",
                    detail: missionControl.approvals.isEmpty ? "No blocked risky work" : "Review pending actions",
                    tone: missionControl.approvals.isEmpty ? .good : .warning
                )
                MetricTile(
                    label: "Runtime Control",
                    value: missionControl.health.controlPreset.title,
                    detail: missionControl.health.controlPreset.summary,
                    tone: controlTone(for: missionControl.health.controlPreset)
                )
                MetricTile(
                    label: "Alerts",
                    value: "\(missionControl.alerts.count)",
                    detail: missionControl.alerts.first?.title ?? "No critical blockers detected",
                    tone: missionControl.alerts.contains(where: { $0.severity == .critical }) ? .danger : (missionControl.alerts.isEmpty ? .good : .warning)
                )
                MetricTile(
                    label: "Trace Sessions",
                    value: "\(missionControl.traceSessions.count)",
                    detail: missionControl.traceSessions.isEmpty ? "No recent evidence yet" : "Recent runtime evidence available",
                    tone: missionControl.traceSessions.isEmpty ? .neutral : .good
                )
            }

            HStack(spacing: 10) {
                Button("Refresh Mission Control") {
                    Task { await store.refreshMissionControl() }
                }
                .buttonStyle(ControllerPrimaryButtonStyle())

                Button("Open Control") {
                    store.selectedSection = .control
                }
                .buttonStyle(ControllerSecondaryButtonStyle())

                Button("Review Health") {
                    store.selectedSection = .health
                }
                .buttonStyle(ControllerSecondaryButtonStyle())
            }

            if let topAlert = missionControl.alerts.first {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: topAlert.severity == .critical ? "exclamationmark.octagon.fill" : "megaphone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(alertTone(for: topAlert.severity).color)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(topAlert.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(topAlert.message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ControllerTheme.muted)
                    }
                }
                .padding(12)
                .background(alertTone(for: topAlert.severity).color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var headline: String {
        if store.hostConnection.requiresAttention {
            return "Reconnect the host bridge before you continue."
        }
        if missionControl.health.permissions.contains(where: { !$0.granted }) {
            return "Grant the remaining permissions to unlock full control."
        }
        if !missionControl.health.storageReady {
            return "Fix local storage before trusting fresh runtime evidence."
        }
        if !missionControl.approvals.isEmpty {
            return "Pending approvals are the main thing blocking forward progress."
        }
        return "The controller is ready for supervised operator work."
    }

    private var summary: String {
        if let firstPrompt = missionControl.recommendedPrompts.first {
            return firstPrompt
        }
        return "Use Mission Control to scan readiness, inspect live evidence, and choose the next safe action."
    }

    private var readinessLabel: String {
        if store.hostConnection.requiresAttention {
            return "Host Attention"
        }
        if missionControl.health.permissions.contains(where: { !$0.granted }) || !missionControl.health.storageReady {
            return "Readiness Attention"
        }
        return missionControl.approvals.isEmpty ? "Operator Ready" : "Review Approvals"
    }

    private var readinessTone: StatusBadge.Tone {
        if store.hostConnection.requiresAttention {
            return .danger
        }
        if missionControl.health.permissions.contains(where: { !$0.granted }) || !missionControl.health.storageReady {
            return .warning
        }
        return missionControl.approvals.isEmpty ? .good : .warning
    }

    private func alertTone(for severity: AlertSeverity) -> StatusBadge.Tone {
        switch severity {
        case .info:
            return .neutral
        case .warning:
            return .warning
        case .critical:
            return .danger
        }
    }

    private func controlTone(for preset: RuntimeControlPreset) -> StatusBadge.Tone {
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
}

private struct MissionAlertsCard: View {
    let missionControl: MissionControlSnapshot

    var body: some View {
        PanelCard("Alerts & Approvals", subtitle: "High-signal issues that may block operator flow") {
            if missionControl.alerts.isEmpty && missionControl.approvals.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No active risks",
                    message: "Mission Control is not seeing any blocking alerts or pending approvals."
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(missionControl.alerts) { alert in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(alert.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                StatusBadge(label: alert.severity.rawValue.uppercased(), tone: tone(for: alert.severity))
                            }
                            Text(alert.message)
                                .font(.system(size: 12))
                                .foregroundStyle(ControllerTheme.muted)
                        }
                        .padding(12)
                        .background(tone(for: alert.severity).color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(tone(for: alert.severity).color.opacity(0.16), lineWidth: 1)
                        )
                    }

                    ForEach(missionControl.approvals.prefix(3)) { approval in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(approval.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Text(approval.reason)
                                .font(.system(size: 12))
                                .foregroundStyle(ControllerTheme.muted)
                        }
                        .padding(12)
                        .background(ControllerTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func tone(for severity: AlertSeverity) -> StatusBadge.Tone {
        switch severity {
        case .info: return .neutral
        case .warning: return .warning
        case .critical: return .danger
        }
    }
}

private enum DashboardChartMode {
    case line
    case bar
}

private struct DashboardSeriesCard: View {
    let series: DashboardSeries
    let mode: DashboardChartMode

    var body: some View {
        PanelCard(series.title, subtitle: series.subtitle) {
            if series.points.isEmpty {
                EmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No chart data",
                    message: "Run actions or recipes to populate this runtime series."
                )
                .frame(height: 240)
            } else {
                Chart(series.points) { point in
                    switch mode {
                    case .line:
                        LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent)
                        AreaMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent.opacity(0.16))
                    case .bar:
                        BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
                            .foregroundStyle(ControllerTheme.accent.gradient)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(minWidth: 260, minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityTimelineCard: View {
    let entries: [MissionActivityEntry]

    var body: some View {
        PanelCard("Recent Activity", subtitle: "Recent controller and runtime activity") {
            if entries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.badge.questionmark",
                    title: "No recent activity",
                    message: "Run a manual action or recipe to generate live activity for Mission Control."
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color(for: entry.tone))
                                .frame(width: 10, height: 10)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(entry.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(ControllerTheme.muted)
                            }
                            Spacer()
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ControllerTheme.muted)
                        }
                        .padding(12)
                        .background(ControllerTheme.panelRaised.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func color(for tone: DashboardTone) -> Color {
        switch tone {
        case .neutral: return ControllerTheme.accent
        case .good: return ControllerTheme.success
        case .warning: return ControllerTheme.warning
        case .danger: return ControllerTheme.danger
        }
    }
}

private struct WorkflowExperimentCard: View {
    let workflows: [ControllerWorkflowDiagnostics]
    let experiments: [ControllerExperimentDiagnostics]

    var body: some View {
        PanelCard("Workflows & Experiments", subtitle: "Reusable knowledge and bounded candidates") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Top workflows")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if workflows.isEmpty {
                    Text("No workflows promoted yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workflows, id: \.id) { workflow in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workflow.goalPattern)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                                Text(workflow.promotionStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(ControllerTheme.muted)
                            }
                            Spacer()
                            StatusBadge(label: "\(Int(workflow.successRate * 100))%", tone: workflow.successRate >= 0.75 ? .good : .warning)
                        }
                    }
                }

                Divider()

                Text("Recent experiments")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if experiments.isEmpty {
                    Text("No bounded experiments recorded.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(experiments, id: \.id) { experiment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(experiment.id)
                                .font(.system(size: 13, weight: .semibold))
                            Text("Candidates: \(experiment.candidateCount) • Successes: \(experiment.succeededCandidateCount)")
                                .font(.system(size: 11))
                                .foregroundStyle(ControllerTheme.muted)
                        }
                    }
                }
            }
        }
    }
}
