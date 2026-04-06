// RootView+Settings.swift — Settings workspace and inspector views.

import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct SettingsWorkspaceView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                PanelCard("Runtime Control", subtitle: "Whole-runtime autonomy mode, applied through the host") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.selectedControlPreset?.title ?? "Loading runtime control")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(ControllerTheme.ink)
                                Text(store.selectedControlPreset?.summary ?? "The host reports the active runtime preset here after bootstrap.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ControllerTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if let policyMode = store.health?.policyMode {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Policy Mode")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(ControllerTheme.muted)
                                    Text(policyMode)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(ControllerTheme.ink)
                                }
                            }
                        }

                        ForEach(RuntimeControlPreset.allCases) { preset in
                            Button {
                                Task { await store.setControlPreset(preset) }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.title)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(ControllerTheme.ink)
                                        Text(preset.summary)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(ControllerTheme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    if store.selectedControlPreset == preset {
                                        StatusBadge(
                                            label: store.isUpdatingControlPreset ? "Applying" : "Active",
                                            tone: store.isUpdatingControlPreset ? .neutral : .good
                                        )
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(store.selectedControlPreset == preset ? ControllerTheme.panelRaised : Color.white.opacity(0.45))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(store.selectedControlPreset == preset ? ControllerTheme.accent.opacity(0.28) : ControllerTheme.border, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isUpdatingControlPreset && store.selectedControlPreset != preset)
                        }

                        Text("Full Control still keeps the hard runtime safety blocks. AI Decides blocks irreversible or external risk and asks for review on the rest.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ControllerTheme.muted)
                    }
                }

                PanelCard("Session Settings", subtitle: "Controller-local behavior, not runtime policy") {
                    Toggle("Auto refresh monitoring", isOn: $store.autoRefreshEnabled)
                        .onChange(of: store.autoRefreshEnabled) { _, _ in
                            Task { await store.updateMonitoring() }
                        }
                    TextField("Monitored app", text: $store.monitorAppName)
                        .textFieldStyle(.roundedBorder)
                    Button("Apply Monitor Settings") {
                        Task { await store.updateMonitoring() }
                    }
                }

                PanelCard("Layout", subtitle: "Adjust sidebar, dock, and workspace sizing live") {
                    ControllerLayoutEditor()
                }

                PanelCard("Operations", subtitle: "Open runtime storage used by the controller") {
                    Button("Open Trace Directory") {
                        if let path = store.health?.traceDirectoryPath {
                            store.openArtifact(path)
                        }
                    }
                    Button("Open Recipe Directory") {
                        if let path = store.health?.recipeDirectoryPath {
                            store.openArtifact(path)
                        }
                    }
                    Button("Reveal Application Support") {
                        store.revealDataFolder()
                    }
                    Button("Reveal Logs") {
                        store.revealLogsFolder()
                    }
                    Button("Export Diagnostics") {
                        store.exportDiagnostics()
                    }
                    Button("Reset App Data") {
                        store.resetControllerData()
                    }
                }

                PanelCard("Onboarding + Help", subtitle: "Product setup, help, and optional vision bootstrap") {
                    Button("Run Setup Wizard") {
                        store.reopenOnboarding()
                    }
                    Button("Open Help") {
                        store.openHelp()
                    }
                    Button("Open Release Notes") {
                        store.openReleaseNotes()
                    }
                    Button("Install Vision Bootstrap") {
                        Task { await store.installVisionBootstrap() }
                    }
                    Button("Repair Vision Bootstrap") {
                        Task { await store.repairVisionBootstrap() }
                    }
                }
            }
            .padding(layout.workspacePaddingValue)
        }
    }
}

struct SettingsInspectorView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            PanelCard("Controller Session", subtitle: "Host process and active monitor details") {
                if let session = store.session {
                    KVRow(key: "Session ID", value: session.id, monospaced: true)
                    KVRow(key: "Host PID", value: "\(session.hostProcessID)", monospaced: true)
                    KVRow(key: "Active App", value: session.activeAppName ?? "Unknown")
                    KVRow(key: "Started", value: session.startedAt.formatted(date: .abbreviated, time: .standard))
                } else {
                    EmptyStateView(
                        systemImage: "switch.2",
                        title: "No Session Yet",
                        message: "The host session will appear here after the controller bootstraps."
                    )
                    .frame(height: 240)
                }
            }
            .padding(layout.workspacePaddingValue)
        }
    }
}
