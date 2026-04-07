import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct RootView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout
    @State private var showingLayoutControls = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 320, ideal: layout.sidebarColumnWidth, max: 520)
        } content: {
            content
        } detail: {
            CopilotDockView(store: store) {
                inspector
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: layout.inspectorColumnWidth, max: 760)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: layout.minimumWindowWidth, minHeight: 900)
        .background(ControllerBackdrop())
        .safeAreaInset(edge: .top) {
            VStack(spacing: 10) {
                ControllerShellHeader(store: store)
                ControllerStatusBar(store: store)
            }
            .padding(.horizontal, layout.workspacePaddingValue)
            .padding(.top, 8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Toggle(isOn: $store.autoRefreshEnabled) {
                    Label("Auto Refresh", systemImage: store.autoRefreshEnabled ? "wave.3.right" : "pause.circle")
                }
                .toggleStyle(.button)
                .onChange(of: store.autoRefreshEnabled) { oldValue, _ in
                    Task { await store.updateMonitoring(previousValue: oldValue) }
                }

                Button {
                    showingLayoutControls.toggle()
                } label: {
                    Label("Layout", systemImage: "sidebar.leading")
                }
                .popover(isPresented: $showingLayoutControls, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Layout Controls")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(ControllerTheme.ink)
                        ControllerLayoutEditor(compact: true)
                    }
                    .padding(20)
                    .frame(width: 360)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.isBusy {
                ProgressView()
                    .controlSize(.large)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .overlay {
            if store.showOnboarding {
                OnboardingOverlayView(store: store)
            }
        }
        .alert(
            "Controller Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            ),
            actions: {
                if store.hostConnection.requiresAttention,
                   store.errorMessage == store.hostConnection.detailText
                {
                    Button("Retry Host") {
                        store.errorMessage = nil
                        Task { await store.retryHostConnection() }
                    }
                }
                Button("OK", role: .cancel) {
                    store.errorMessage = nil
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
        .task {
            await store.start()
            if store.isLoaded {
                await store.updateMonitoring()
            }
        }
        .onChange(of: store.selectedSection) { _, section in
            store.scheduleRefreshForSelectedSection(section)
        }
        .onDisappear {
            store.cancelSectionRefreshWork()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: layout.stackSpacing) {
            PanelCard("Oracle Controller", subtitle: "Supervised local operator console", style: .hero) {
                Text("Control the runtime, inspect traces, review approvals, and keep local readiness visible from one native workspace.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)

                HStack(spacing: 8) {
                    StatusBadge(label: store.selectedSection.title, tone: .neutral)
                    StatusBadge(label: store.autoRefreshEnabled ? "Auto Refresh" : "Manual", tone: store.autoRefreshEnabled ? .good : .warning)
                    if let appName = store.snapshot?.observation.appName ?? store.session?.activeAppName {
                        StatusBadge(label: appName, tone: .neutral)
                    }
                }
            }

            List(WorkspaceSection.allCases, selection: $store.selectedSection) { section in
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18)
                        .foregroundStyle(store.selectedSection == section ? ControllerTheme.accent : ControllerTheme.muted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(ControllerTheme.ink)
                        Text(sectionDescription(for: section))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ControllerTheme.muted)
                    }
                }
                .padding(.vertical, 6)
                .tag(section)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(ControllerTheme.panelRaised.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
            )

            PanelCard("Session", subtitle: "Current operator context", style: .muted) {
                if let session = store.session {
                    MetricTile(
                        label: "Runtime",
                        value: session.activeAppName ?? "No app",
                        detail: session.autoRefreshEnabled ? "Automatic monitor refresh is active." : "Monitoring is paused.",
                        tone: session.autoRefreshEnabled ? .good : .warning
                    )
                    KVRow(key: "Session ID", value: session.id, monospaced: true)
                } else {
                    Text("The controller will populate runtime context after the first successful bootstrap.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                }

                if let inlineMessage = store.inlineMessage, !inlineMessage.isEmpty {
                    Text(inlineMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }
        }
        .padding(max(12, layout.workspacePaddingValue - 4))
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedSection {
        case .missionControl:
            MissionControlWorkspaceView(store: store)
        case .control:
            ControlWorkspaceView(store: store)
        case .recipes:
            RecipesWorkspaceView(store: store)
        case .traces:
            TracesWorkspaceView(store: store)
        case .diagnostics:
            DiagnosticsWorkspaceView(store: store)
        case .health:
            HealthWorkspaceView(store: store)
        case .settings:
            SettingsWorkspaceView(store: store)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch store.selectedSection {
        case .missionControl:
            MissionControlInspectorView(store: store)
        case .control:
            ControlInspectorView(store: store)
        case .recipes:
            RecipeInspectorView(store: store)
        case .traces:
            TraceInspectorView(store: store)
        case .diagnostics:
            DiagnosticsInspectorView(store: store)
        case .health:
            HealthInspectorView(store: store)
        case .settings:
            SettingsInspectorView(store: store)
        }
    }
}

private struct ControllerShellHeader: View {
    @Bindable var store: ControllerStore

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Oracle Controller")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(ControllerTheme.ink)
                Text(sectionSummary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)
            }

            Spacer()

            HStack(spacing: 8) {
                StatusBadge(label: store.selectedSection.title, tone: .neutral)
                if let appName = store.snapshot?.observation.appName ?? store.session?.activeAppName {
                    StatusBadge(label: appName, tone: .good)
                }
                if store.hostConnection.requiresAttention {
                    StatusBadge(label: "Host Attention", tone: .danger)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ControllerTheme.panelRaised.opacity(0.92), ControllerTheme.panelTint.opacity(0.84)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(ControllerTheme.borderStrong.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: ControllerTheme.shadow, radius: 18, y: 10)
        )
    }

    private var sectionSummary: String {
        switch store.selectedSection {
        case .missionControl:
            return "Scan readiness, recent activity, and the next safest move."
        case .control:
            return "Operate the runtime manually with visible host, policy, and approval state."
        case .recipes:
            return "Shape repeatable workflows without losing traceability or approval control."
        case .traces:
            return "Inspect step-level evidence, hashes, outcomes, and linked artifacts."
        case .diagnostics:
            return "Review graph, workflow, repository, and host diagnostics in one place."
        case .health:
            return "Keep permissions, storage, host readiness, and optional integrations honest."
        case .settings:
            return "Manage setup, data, diagnostics exports, and optional packaged assets."
        }
    }
}

private func sectionDescription(for section: WorkspaceSection) -> String {
    switch section {
    case .missionControl:
        return "Alerts, KPIs, and recent runtime signals"
    case .control:
        return "Manual actions and approvals"
    case .recipes:
        return "Replayable workflows"
    case .traces:
        return "Execution evidence"
    case .diagnostics:
        return "Graph and system diagnostics"
    case .health:
        return "Permissions and local readiness"
    case .settings:
        return "Setup and maintenance"
    }
}

