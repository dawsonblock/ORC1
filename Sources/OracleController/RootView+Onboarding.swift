// RootView+Onboarding.swift — Setup wizard overlay view.

import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct OnboardingOverlayView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Oracle Controller Setup")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(store.onboardingStep.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.onboardingStep.rawValue + 1) / \(OnboardingStep.allCases.count)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                content

                Divider()

                HStack {
                    Button("Back") {
                        store.retreatOnboarding()
                    }
                    .disabled(store.onboardingStep == .welcome)

                    Spacer()

                    if store.onboardingStep == .ready {
                        Button("Finish") {
                            store.completeOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(store.onboardingStep == .vision ? "Skip for Now" : "Continue") {
                            store.advanceOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(28)
            .frame(width: 760)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 18)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.onboardingStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Oracle Controller is the packaged local console for Oracle OS. It keeps the existing execution truth path intact while giving you a guided setup, approvals, traces, recipes, and diagnostics in one app.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Runs local-only and supervised.",
                    "Embeds the controller host inside the app bundle.",
                    "Stores app data under Application Support instead of the repo.",
                ])
            }

        case .accessibility:
            permissionStep(
                title: "Grant Accessibility",
                detail: store.health?.permissions.first(where: { $0.id == "accessibility" })?.detail
                    ?? "Oracle Controller needs Accessibility access to inspect and act on applications.",
                granted: store.health?.permissions.first(where: { $0.id == "accessibility" })?.granted == true,
                buttonTitle: "Open Accessibility Settings",
                action: { store.openAccessibilitySettings() }
            )

        case .screenRecording:
            permissionStep(
                title: "Grant Screen Recording",
                detail: store.health?.permissions.first(where: { $0.id == "screen-recording" })?.detail
                    ?? "Screen Recording powers the live monitor and screenshot-backed diagnostics.",
                granted: store.health?.permissions.first(where: { $0.id == "screen-recording" })?.granted == true,
                buttonTitle: "Open Screen Recording Settings",
                action: { store.openScreenRecordingSettings() }
            )

        case .runtime:
            VStack(alignment: .leading, spacing: 12) {
                onboardingFacts([
                    "Runtime version: \(store.health?.runtimeVersion ?? "Unknown")",
                    "Bundled host: \(store.productStatus?.bundledHelperAvailable == true ? "available" : "missing")",
                    "Host bridge: \(store.hostConnection.label)",
                    "Writable storage: \(store.health.map { $0.storageReady ? "Ready" : "Attention" } ?? "Unknown")",
                    "App bundle mode: \(store.health?.runningFromAppBundle == true ? "enabled" : "development")",
                    "Application Support: \(store.health?.applicationSupportPath ?? store.productStatus?.applicationSupportPath ?? "Unknown")",
                ])

                if store.hostConnection.requiresAttention {
                    hostReadinessCard
                }

                if let health = store.health, !health.storageIssues.isEmpty {
                    storageReadinessCard
                }

                if let productStatus = store.productStatus, productStatus.migrationStatus.didMigrateAnything {
                    Text("Imported existing controller data so the packaged app can pick up where the developer setup left off.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

        case .vision:
            VStack(alignment: .leading, spacing: 12) {
                Text("Vision is optional. Core Accessibility-based control works immediately once permissions are granted. You can install or repair the packaged vision bootstrap here and enable the sidecar later.")
                    .font(.system(size: 14))
                HStack(spacing: 10) {
                    Button("Install Vision Bootstrap") {
                        Task { await store.installVisionBootstrap() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Repair Vision") {
                        Task { await store.repairVisionBootstrap() }
                    }
                }
                onboardingFacts([
                    "Bundled assets: \(store.productStatus?.bundledVisionBootstrapAvailable == true ? "available" : "missing")",
                    "Installed location: \(store.productStatus?.visionInstallPath ?? "Unknown")",
                    "Installed now: \(store.productStatus?.visionInstalled == true ? "yes" : "no")",
                ])
            }

        case .recipes:
            VStack(alignment: .leading, spacing: 12) {
                Text("The app seeds bundled sample recipes into your personal data directory the first time it launches. Quick-start tasks are then available from the Recipes and Control sections.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Bundled sample recipes: \(store.productStatus?.bundledSampleRecipesAvailable == true ? "available" : "missing")",
                    "Seeded recipes: \(store.productStatus?.migrationStatus.seededSampleRecipes ?? 0)",
                    "Recipe library path: \(store.health?.recipeDirectoryPath ?? store.productStatus?.recipesPath ?? "Unknown")",
                ])
            }

        case .ready:
            VStack(alignment: .leading, spacing: 12) {
                Text("The packaged controller is ready. You can start with the manual operator console, run a sample recipe, or stay in the health/settings sections until everything is green.")
                    .font(.system(size: 14))
                onboardingFacts([
                    "Quick actions live on the Control page.",
                    "Risky actions still require approval.",
                    "You can reopen this setup flow from the Oracle Controller menu or Settings.",
                ])
            }
        }
    }

    private var hostReadinessCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ControllerTheme.warning)

            VStack(alignment: .leading, spacing: 4) {
                Text("Host Bridge Requires Attention")
                    .font(.system(size: 12, weight: .semibold))
                Text(store.hostConnection.detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Retry Host") {
                Task { await store.retryHostConnection() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(ControllerTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var storageReadinessCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "internaldrive.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ControllerTheme.warning)

            VStack(alignment: .leading, spacing: 6) {
                Text("Local Storage Requires Attention")
                    .font(.system(size: 12, weight: .semibold))

                if let health = store.health {
                    ForEach(health.storageIssues) { location in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.title)
                                .font(.system(size: 12, weight: .medium))
                            Text(location.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let detail = location.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(ControllerTheme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func permissionStep(
        title: String,
        detail: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                StatusBadge(label: granted ? "Granted" : "Required", tone: granted ? .good : .warning)
            }
            Text(detail)
                .font(.system(size: 14))
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }

    private func onboardingFacts(_ facts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts, id: \.self) { fact in
                Label(fact, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(ControllerTheme.accent)
            }
        }
    }
}
