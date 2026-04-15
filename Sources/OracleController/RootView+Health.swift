// RootView+Health.swift — Health workspace and inspector views.

import AppKit
import Foundation
import OracleControllerShared
import SwiftUI

struct HealthWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard(
                    "Readiness Center",
                    subtitle: "Guided setup, recovery, and optional integrations"
                ) {
                    ControllerReadinessSummaryContent(store: store)
                }

                PanelCard(
                    "System Detail", subtitle: "Permissions, sidecar state, and local configuration"
                ) {
                    if let health = store.health {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                KVRow(key: "Runtime", value: health.runtimeVersion)
                                KVRow(key: "Recipes", value: "\(health.recipeCount)")
                            }
                            GridRow {
                                KVRow(
                                    key: "Sidecar",
                                    value: sidecarStatusValue(store: store, health: health))
                                KVRow(key: "Model", value: health.visionModelPath ?? "Unknown")
                            }
                            GridRow {
                                KVRow(key: "Runtime Control", value: health.controlPreset.title)
                                KVRow(key: "Policy Mode", value: health.policyMode)
                            }
                            GridRow {
                                KVRow(key: "Host Bridge", value: store.hostConnection.label)
                                KVRow(
                                    key: "Approval Broker",
                                    value: health.approvalBrokerActive ? "Active" : "Offline")
                            }
                            GridRow {
                                KVRow(
                                    key: "Controller", value: controllerStatusValue(health: health))
                                KVRow(key: "Copilot", value: copilotStatusValue(store: store))
                            }
                            GridRow {
                                KVRow(
                                    key: "Bundle Mode",
                                    value: health.runningFromAppBundle
                                        ? "Packaged App" : "Developer")
                                KVRow(
                                    key: "Bundled Host",
                                    value: health.bundledHostAvailable ? "Embedded" : "Missing")
                            }
                            GridRow {
                                KVRow(
                                    key: "Writable Storage",
                                    value: health.storageReady ? "Ready" : "Attention")
                                KVRow(key: "Trace Dir", value: health.traceDirectoryPath)
                            }
                            GridRow {
                                KVRow(key: "Recipe Dir", value: health.recipeDirectoryPath)
                                KVRow(key: "App Support", value: health.applicationSupportPath)
                            }
                            GridRow {
                                KVRow(key: "Logs", value: health.logsDirectoryPath)
                                KVRow(key: "Graph DB", value: health.graphDatabasePath)
                            }
                            GridRow {
                                KVRow(key: "Vision Install", value: health.visionInstallPath)
                                KVRow(key: "Recipes", value: "\(health.recipeCount)")
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "cross.case.fill",
                            title: "No Health Snapshot",
                            message: store.hostConnection.requiresAttention
                                ? store.hostConnection.detailText
                                : "Refresh health to inspect permissions, local storage, sidecar availability, and runtime directories."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard(
                    "Local Storage",
                    subtitle: "Writable controller data paths under Application Support"
                ) {
                    if let health = store.health {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(health.storageLocations) { location in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(location.title)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(location.path)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if let detail = location.detail, !detail.isEmpty {
                                            Text(detail)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    StatusBadge(
                                        label: location.writable ? "Writable" : "Attention",
                                        tone: location.writable ? .good : .warning)
                                }
                                .padding(12)
                                .background(
                                    Color.white.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            if !health.storageIssues.isEmpty {
                                Text(
                                    "Fix write access for the flagged paths before relying on traces, approvals, recipes, or graph persistence."
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "internaldrive",
                            title: "No Storage Snapshot",
                            message: "Refresh health to inspect local controller data paths."
                        )
                        .frame(height: 180)
                    }
                }

                PanelCard(
                    "Permissions", subtitle: "System access required for production-grade control"
                ) {
                    if let permissions = store.health?.permissions, !permissions.isEmpty {
                        ForEach(permissions) { permission in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(permission.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(permission.detail ?? "")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(
                                    label: permission.granted ? "Granted" : "Required",
                                    tone: permission.granted ? .good : .warning)
                            }
                            .padding(12)
                            .background(
                                Color.white.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                PanelCard(
                    "Product Setup",
                    subtitle: "Packaged runtime, diagnostics, and optional vision bootstrap"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let productStatus = store.productStatus {
                            KVRow(
                                key: "Build",
                                value:
                                    "\(productStatus.buildVersion) (\(productStatus.buildNumber))")
                            KVRow(
                                key: "Vision Assets",
                                value: productStatus.bundledVisionBootstrapAvailable
                                    ? "Bundled" : "Missing")
                            KVRow(
                                key: "Vision Installed",
                                value: productStatus.visionInstalled ? "Yes" : "No")
                            if !productStatus.migrationStatus.migratedLegacyItems.isEmpty {
                                KVRow(
                                    key: "Imported",
                                    value: productStatus.migrationStatus.migratedLegacyItems.joined(
                                        separator: ", ")
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Retry Host Connection") {
                                Task { await store.retryHostConnection() }
                            }
                            Button("Install Vision Bootstrap") {
                                Task { await store.installVisionBootstrap() }
                            }
                            Button("Repair Vision") {
                                Task { await store.repairVisionBootstrap() }
                            }
                            Button("Export Diagnostics") {
                                store.exportDiagnostics()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func controllerStatusValue(health: HealthStatus) -> String {
        if store.hostConnection.phase == .launching {
            return "Starting"
        }
        if store.hostConnection.requiresAttention {
            return "Offline"
        }
        return health.controllerConnected ? "Connected" : "Offline"
    }
}

struct HealthInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            PanelCard("System Summary", subtitle: "What still blocks a frictionless operator loop")
            {
                ControllerReadinessSummaryContent(
                    store: store,
                    taskLimit: 5,
                    showsPrimaryAction: false,
                    showsOptionalTasks: false
                )

                if let health = store.health {
                    Divider()
                    KVRow(key: "Host Bridge", value: store.hostConnection.label)
                    KVRow(key: "Host Detail", value: store.hostConnection.detailText)
                    KVRow(key: "Copilot", value: copilotStatusValue(store: store))
                    KVRow(key: "Sidecar Version", value: health.visionSidecarVersion ?? "Unknown")
                    KVRow(
                        key: "Approval Broker",
                        value: health.approvalBrokerActive ? "Active" : "Offline")
                    KVRow(key: "Controller", value: controllerStatusValue(health: health))
                    KVRow(key: "Runtime Control", value: health.controlPreset.title)
                    KVRow(key: "Policy Mode", value: health.policyMode)
                    KVRow(key: "Local Storage", value: health.storageReady ? "Ready" : "Attention")
                    KVRow(
                        key: "App Support", value: health.applicationSupportPath, monospaced: true)
                    KVRow(key: "Logs", value: health.logsDirectoryPath, monospaced: true)
                    KVRow(
                        key: "Trace Directory", value: health.traceDirectoryPath, monospaced: true)
                    KVRow(
                        key: "Recipe Directory", value: health.recipeDirectoryPath, monospaced: true
                    )
                    KVRow(
                        key: "Project Memory", value: health.projectMemoryDirectoryPath,
                        monospaced: true)
                    KVRow(
                        key: "Experiments", value: health.experimentsDirectoryPath, monospaced: true
                    )
                    KVRow(key: "Graph DB", value: health.graphDatabasePath, monospaced: true)
                }
            }
            .padding(20)
        }
    }

    private func controllerStatusValue(health: HealthStatus) -> String {
        if store.hostConnection.phase == .launching {
            return "Starting"
        }
        if store.hostConnection.requiresAttention {
            return "Offline"
        }
        return health.controllerConnected ? "Connected" : "Offline"
    }
}

@MainActor
private func sidecarStatusValue(store: ControllerStore, health: HealthStatus) -> String {
    if health.visionSidecarRunning {
        return "Running"
    }
    if store.productStatus?.visionInstalled == true {
        return "Installed, Offline"
    }
    return "Optional"
}

@MainActor
private func copilotStatusValue(store: ControllerStore) -> String {
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
