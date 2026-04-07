// RootView+Control.swift — Control workspace views.

import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct ControlWorkspaceView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                controlStatusRow

                HStack(alignment: .top, spacing: layout.stackSpacing) {
                    PanelCard("Live Monitor", subtitle: "Low-frequency screenshot stream", style: .hero) {
                        ScreenshotPreview(screenshot: store.snapshot?.screenshot)
                            .frame(maxWidth: .infinity, minHeight: 420)
                    }
                    .frame(maxWidth: .infinity)

                    ActionComposerCard(store: store)
                        .frame(width: layout.utilityPanelWidth)
                }

                HStack(alignment: .top, spacing: layout.stackSpacing) {
                    PanelCard("Visible Elements", subtitle: "\(store.filteredElements.count) in current observation") {
                        TextField("Filter elements", text: $store.elementSearchText)
                            .textFieldStyle(.roundedBorder)

                        if store.filteredElements.isEmpty {
                            EmptyStateView(
                                systemImage: "rectangle.dashed",
                                title: "No Elements",
                                message: "Refresh the snapshot or choose another app to inspect visible UI elements."
                            )
                            .frame(height: 220)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(store.filteredElements) { element in
                                        Button {
                                            store.selectedElementID = element.id
                                        } label: {
                                            ElementListRow(
                                                element: element,
                                                isSelected: store.selectedElementID == element.id,
                                                fill: elementRowFill(for: element)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(element.id == store.selectedElementID ? ControllerTheme.accent.opacity(0.4) : ControllerTheme.border, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(minHeight: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    PanelCard("Action Timeline", subtitle: "Recent controller action results") {
                        if store.recentActions.isEmpty {
                            EmptyStateView(
                                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                                title: "No Recent Actions",
                                message: "Run a manual action or recipe to start building an execution timeline."
                            )
                            .frame(height: 220)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.recentActions) { action in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(action.request.displayTitle)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(action.summaryText)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 6) {
                                            StatusBadge(label: action.statusLabel, tone: tone(for: action))
                                            Text("\(Int(action.elapsedMs)) ms")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(ControllerTheme.muted)
                                        }
                                    }
                                    .padding(12)
                                    .background(ControllerTheme.panelRaised.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(width: layout.railPanelWidth)
                }

                ApprovalQueueCard(store: store)
            }
            .padding(layout.workspacePaddingValue)
        }
    }

    private var controlStatusRow: some View {
        PanelCard("Operator Console", subtitle: "Supervised local runtime control", style: .hero) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.snapshot?.observation.appName ?? "No app selected")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(ControllerTheme.ink)
                        Text(store.snapshot?.observation.windowTitle ?? "No active window")
                            .font(.system(size: 14))
                            .foregroundStyle(ControllerTheme.muted)
                        if let url = store.snapshot?.observation.url {
                            Text(url)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(ControllerTheme.accent)
                                .lineLimit(1)
                        }
                        if let productStatus = store.productStatus {
                            Text("Build \(productStatus.buildVersion) (\(productStatus.buildNumber))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 8) {
                            StatusBadge(label: store.hostConnection.label, tone: hostTone)
                            StatusBadge(label: sidecarLabel, tone: sidecarTone)
                            StatusBadge(label: store.autoRefreshEnabled ? "Monitoring" : "Paused", tone: monitorTone)
                        }
                        if let permissions = store.health?.permissions {
                            HStack(spacing: 8) {
                                ForEach(permissions) { permission in
                                    StatusBadge(
                                        label: permission.granted ? permission.title : "\(permission.title) Required",
                                        tone: permission.granted ? .good : .warning
                                    )
                                }
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    MetricTile(
                        label: "Host",
                        value: store.hostConnection.label,
                        detail: store.hostConnection.detailText,
                        tone: hostTone
                    )
                    MetricTile(
                        label: "Vision Sidecar",
                        value: sidecarLabel,
                        detail: sidecarDetail,
                        tone: sidecarTone
                    )
                    MetricTile(
                        label: "Approvals",
                        value: store.health?.approvalBrokerActive == true ? "Broker Ready" : "Broker Offline",
                        detail: approvalBrokerDetail,
                        tone: approvalBrokerTone
                    )
                    MetricTile(
                        label: "Monitor",
                        value: store.autoRefreshEnabled ? "Active" : "Paused",
                        detail: monitorDetail,
                        tone: monitorTone
                    )
                }

                HStack(spacing: 10) {
                    Button("Refresh Snapshot") {
                        Task { await store.refreshNow() }
                    }
                    .buttonStyle(ControllerPrimaryButtonStyle())

                    Menu {
                        ForEach(RuntimeControlPreset.allCases) { preset in
                            Button {
                                Task { await store.setControlPreset(preset) }
                            } label: {
                                if store.selectedControlPreset == preset {
                                    Label(preset.title, systemImage: "checkmark")
                                } else {
                                    Text(preset.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Runtime Control")
                            Text(store.selectedControlPreset?.title ?? "Loading")
                                .foregroundStyle(ControllerTheme.accent)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(ControllerTheme.panelRaised.opacity(0.92), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ControllerTheme.borderStrong.opacity(0.7), lineWidth: 1)
                        )
                    }
                    .disabled(store.isUpdatingControlPreset)

                    Button("Run Setup Wizard") {
                        store.reopenOnboarding()
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())

                    Button("Open Recipes") {
                        store.selectedSection = .recipes
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())

                    Button("Reveal Data Folder") {
                        store.revealDataFolder()
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())

                    Button("Export Diagnostics") {
                        store.exportDiagnostics()
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())

                    Button("Open Help") {
                        store.openHelp()
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())
                }

                Text("Manual Action sends runtime work through the host bridge. Setup, diagnostics, and help buttons here are controller-local support tools.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)

                if store.hostConnection.requiresAttention {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(hostTone.color)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host Bridge Requires Attention")
                                .font(.system(size: 12, weight: .semibold))
                            Text(store.hostConnection.detailText)
                                .font(.system(size: 11))
                                .foregroundStyle(ControllerTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Retry Host") {
                            Task { await store.retryHostConnection() }
                        }
                        .buttonStyle(ControllerPrimaryButtonStyle())
                    }
                    .padding(12)
                    .background(hostTone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let inlineMessage = store.inlineMessage, !inlineMessage.isEmpty {
                    Text(inlineMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }
        }
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

    private var sidecarLabel: String {
        if store.health?.visionSidecarRunning == true {
            return "Sidecar Ready"
        }
        if store.productStatus?.visionInstalled == true {
            return "Sidecar Offline"
        }
        return "Sidecar Optional"
    }

    private var sidecarTone: StatusBadge.Tone {
        if store.health?.visionSidecarRunning == true {
            return .good
        }
        if store.productStatus?.visionInstalled == true {
            return .warning
        }
        return .neutral
    }

    private var sidecarDetail: String {
        if store.health?.visionSidecarRunning == true {
            return "Computer vision enrichments are available to the host."
        }
        if store.productStatus?.visionInstalled == true {
            return "Installed locally but not connected right now."
        }
        return "Optional sidecar. Core control flows remain available without it."
    }

    private var approvalBrokerTone: StatusBadge.Tone {
        store.health?.approvalBrokerActive == true ? .good : .warning
    }

    private var approvalBrokerDetail: String {
        if store.health?.approvalBrokerActive == true {
            return store.approvalQueue.isEmpty ? "No pending approvals at the moment." : "\(store.approvalQueue.count) request(s) are waiting for a decision."
        }
        return "Approval-protected actions cannot advance until the broker is available."
    }

    private var monitorTone: StatusBadge.Tone {
        store.autoRefreshEnabled ? .good : .warning
    }

    private var monitorDetail: String {
        if store.autoRefreshEnabled {
            return store.snapshot?.observation.appName.map { "Tracking \($0)." } ?? "Watching the current focused application."
        }
        return "Manual refresh only. Snapshot evidence will stay static until refreshed."
    }

    private func elementRowFill(for element: ElementSnapshot) -> Color {
        if element.id == store.selectedElementID {
            return ControllerTheme.accent.opacity(0.12)
        }
        if element.focused {
            return ControllerTheme.success.opacity(0.10)
        }
        return ControllerTheme.panelRaised.opacity(0.9)
    }
}

private struct ElementListRow: View {
    let element: ElementSnapshot
    let isSelected: Bool
    let fill: Color

    private var title: String {
        element.label ?? element.role ?? element.id
    }

    private var subtitle: String {
        element.role ?? element.source
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ControllerTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)
                if let value = element.value, !value.isEmpty {
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundStyle(ControllerTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(
                    label: element.focused ? "Focused" : element.source.uppercased(),
                    tone: element.focused ? .good : .neutral
                )
                Text(String(format: "%.2f", element.confidence))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ControllerTheme.muted)
            }
        }
        .padding(12)
        .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ApprovalQueueCard: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Approvals", subtitle: "Pending runtime approval requests with transient decision feedback") {
            if store.approvalRows.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.shield",
                    title: "No Pending Approvals",
                    message: "Only actions paused awaiting approval appear here. Policy-blocked or rejected actions stay in the action result view."
                )
                .frame(height: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.approvalRows) { row in
                        let approval = row.approval
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(approval.displayTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(approval.reason)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if row.phase != .pending {
                                    StatusBadge(label: phaseLabel(for: row.phase), tone: phaseTone(for: row.phase))
                                }
                                StatusBadge(label: approval.riskLevel.uppercased(), tone: .warning)
                            }
                            HStack {
                                StatusBadge(label: approval.protectedOperation, tone: .danger)
                                StatusBadge(label: approval.appProtectionProfile, tone: .neutral)
                                if let appName = approval.appName {
                                    StatusBadge(label: appName, tone: .neutral)
                                }
                            }
                            HStack {
                                switch row.phase {
                                case .pending:
                                    Button("Approve") {
                                        Task { await store.approveApprovalRequest(approval) }
                                    }
                                    .buttonStyle(ControllerPrimaryButtonStyle())

                                    Button("Reject", role: .destructive) {
                                        Task { await store.rejectApprovalRequest(approval) }
                                    }
                                    .buttonStyle(ControllerSecondaryButtonStyle())

                                case .submitting:
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Decision in flight")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(ControllerTheme.muted)
                                    }

                                case .resolved(let action):
                                    Label(action.resolvedLabel, systemImage: action == .approve ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(action == .approve ? ControllerTheme.success : ControllerTheme.warning)
                                }

                                Spacer()

                                Text(approval.surface.uppercased())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(ControllerTheme.muted)
                            }
                        }
                        .padding(12)
                        .background(backgroundFill(for: row.phase), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private func phaseLabel(for phase: ApprovalRowPhase) -> String {
        switch phase {
        case .pending:
            return "Pending"
        case .submitting(let action):
            return action.pendingLabel
        case .resolved(let action):
            return action.resolvedLabel
        }
    }

    private func phaseTone(for phase: ApprovalRowPhase) -> StatusBadge.Tone {
        switch phase {
        case .pending:
            return .warning
        case .submitting:
            return .neutral
        case .resolved(let action):
            return action == .approve ? .good : .danger
        }
    }

    private func backgroundFill(for phase: ApprovalRowPhase) -> Color {
        switch phase {
        case .pending:
            return ControllerTheme.warning.opacity(0.08)
        case .submitting:
            return ControllerTheme.panelRaised.opacity(0.94)
        case .resolved(let action):
            return action == .approve
                ? ControllerTheme.success.opacity(0.08)
                : ControllerTheme.warning.opacity(0.1)
        }
    }
}

struct ActionComposerCard: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Manual Action", subtitle: "Runtime actions flow through the host bridge; Wait evaluates a condition locally", style: .hero) {
            Picker("Action", selection: $store.actionComposer.kind) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(actionHint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ControllerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                TextField("Target app", text: $store.actionComposer.appName)
                TextField("Window title (optional)", text: $store.actionComposer.windowTitle)
            }
            .textFieldStyle(.roundedBorder)

            switch store.actionComposer.kind {
            case .focus:
                EmptyView()

            case .click:
                TextField("Query / label", text: $store.actionComposer.query)
                    .textFieldStyle(.roundedBorder)
                TextField("Role (optional)", text: $store.actionComposer.role)
                    .textFieldStyle(.roundedBorder)
                TextField("DOM ID (optional)", text: $store.actionComposer.domID)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("X", text: $store.actionComposer.x)
                    TextField("Y", text: $store.actionComposer.y)
                }
                .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Button", text: $store.actionComposer.button)
                    TextField("Count", text: $store.actionComposer.count)
                }
                .textFieldStyle(.roundedBorder)

            case .type:
                TextField("Target field", text: $store.actionComposer.query)
                    .textFieldStyle(.roundedBorder)
                TextField("DOM ID (optional)", text: $store.actionComposer.domID)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $store.actionComposer.text)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(ControllerTheme.panelRaised.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
                Toggle("Clear current value before typing", isOn: $store.actionComposer.clearExisting)

            case .press:
                TextField("Key", text: $store.actionComposer.key)
                    .textFieldStyle(.roundedBorder)
                TextField("Modifiers (comma-separated)", text: $store.actionComposer.modifiers)
                    .textFieldStyle(.roundedBorder)

            case .scroll:
                TextField("Direction", text: $store.actionComposer.direction)
                    .textFieldStyle(.roundedBorder)
                TextField("Amount", text: $store.actionComposer.amount)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("X (optional)", text: $store.actionComposer.x)
                    TextField("Y (optional)", text: $store.actionComposer.y)
                }
                .textFieldStyle(.roundedBorder)

            case .wait:
                TextField("Condition", text: $store.actionComposer.waitCondition)
                    .textFieldStyle(.roundedBorder)
                TextField("Value", text: $store.actionComposer.waitValue)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Timeout (s)", text: $store.actionComposer.timeout)
                    TextField("Interval (s)", text: $store.actionComposer.interval)
                }
                .textFieldStyle(.roundedBorder)
            }

            Button {
                Task { await store.submitAction() }
            } label: {
                Label(store.actionComposer.kind == .wait ? "Evaluate Condition" : "Run Action", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ControllerPrimaryButtonStyle())
        }
    }

    private var actionHint: String {
        switch store.actionComposer.kind {
        case .focus:
            return "Bring a target app and optional window to the foreground before taking any more specific action."
        case .click:
            return "Prefer a label or computed query first, then fall back to DOM IDs or coordinates when needed."
        case .type:
            return "Typing targets a discovered field and can clear the current value before entering text."
        case .press:
            return "Keyboard shortcuts are sent through the host bridge with an optional modifier list."
        case .scroll:
            return "Use semantic direction and amount when possible; coordinates are optional precision overrides."
        case .wait:
            return "Wait is observational only. It evaluates a condition locally instead of executing a runtime mutation."
        }
    }
}

struct ControlInspectorView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                PanelCard("Selected Element", subtitle: "Inspection details for the highlighted control") {
                    if let element = store.selectedElement {
                        KVRow(key: "ID", value: element.id, monospaced: true)
                        KVRow(key: "Label", value: element.label ?? "None")
                        KVRow(key: "Role", value: element.role ?? "None")
                        KVRow(key: "Value", value: element.value ?? "None")
                        KVRow(key: "Source", value: element.source)
                        KVRow(key: "Confidence", value: String(format: "%.2f", element.confidence))
                        KVRow(key: "Frame", value: element.frame.map { "\(Int($0.x)), \(Int($0.y)) - \(Int($0.width))x\(Int($0.height))" } ?? "Unavailable", monospaced: true)
                    } else {
                        EmptyStateView(
                            systemImage: "cursorarrow.motionlines",
                            title: "No Element Selected",
                            message: "Choose a visible element to inspect its identity, source, and confidence."
                        )
                        .frame(height: 240)
                    }
                }

                PanelCard("Verification", subtitle: "Latest action status") {
                    if let result = store.currentActionResult {
                        HStack {
                                StatusBadge(label: result.statusLabel, tone: tone(for: result))
                            if let failureClass = result.failureClass {
                                StatusBadge(label: failureClass, tone: .warning)
                            }
                            if let approvalStatus = result.approvalStatus {
                                StatusBadge(label: approvalStatus, tone: approvalStatus == "pending" ? .warning : .neutral)
                            }
                        }
                        KVRow(key: "Request", value: result.request.displayTitle)
                            KVRow(key: "Message", value: result.summaryText)
                            KVRow(key: "Execution Path", value: result.executionPathSummary)
                        KVRow(key: "Elapsed", value: "\(Int(result.elapsedMs)) ms", monospaced: true)
                            if let verificationStatus = result.verificationStatus {
                                KVRow(key: "Verification", value: verificationStatus)
                            }
                        if let commandCategory = result.commandCategory {
                            KVRow(key: "Command", value: commandCategory)
                        }
                        if let commandSummary = result.commandSummary {
                            KVRow(key: "Summary", value: commandSummary)
                        }
                        if let workspaceRelativePath = result.workspaceRelativePath {
                            KVRow(key: "Path", value: workspaceRelativePath, monospaced: true)
                        }
                        if let buildResultSummary = result.buildResultSummary {
                            KVRow(key: "Build", value: buildResultSummary)
                        }
                        if let testResultSummary = result.testResultSummary {
                            KVRow(key: "Tests", value: testResultSummary)
                        }
                        if let patchID = result.patchID {
                            KVRow(key: "Patch", value: patchID, monospaced: true)
                        }
                        if let protectedOperation = result.protectedOperation {
                            KVRow(key: "Protected Op", value: protectedOperation)
                        }
                        if let appProtectionProfile = result.appProtectionProfile {
                            KVRow(key: "App Profile", value: appProtectionProfile)
                        }
                        if let policyMode = result.policyMode {
                            KVRow(key: "Policy Mode", value: policyMode)
                        }
                        if let approvalRequestID = result.approvalRequestID {
                            KVRow(key: "Approval", value: approvalRequestID, monospaced: true)
                        }
                        if result.blockedByPolicy {
                            KVRow(key: "Policy", value: "Blocked before execution")
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "checkmark.shield",
                            title: "No Verification Yet",
                            message: "Manual actions and recipe runs will surface verification results here."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(layout.workspacePaddingValue)
        }
    }
}

private func tone(for result: ActionRunResult) -> StatusBadge.Tone {
    switch result.disposition {
    case .awaitingApproval:
        return .warning
    case .rejected:
        return .danger
    case .blockedByPolicy:
        return .danger
    case .verifiedExecution:
        return .good
    case .observed:
        return .neutral
    case .partialSuccess:
        return .warning
    case .failed:
        return .danger
    }
}
