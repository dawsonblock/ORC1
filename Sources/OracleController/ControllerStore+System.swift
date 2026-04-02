// ControllerStore+System.swift — Onboarding, system settings, and data management operations.

import AppKit
import Foundation
import OracleControllerShared

extension ControllerStore {
    func reopenOnboarding() {
        onboardingStep = .welcome
        showOnboarding = true
    }

    func advanceOnboarding() {
        if let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) {
            onboardingStep = next
        }
    }

    func retreatOnboarding() {
        if let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) {
            onboardingStep = previous
        }
    }

    func completeOnboarding() {
        productEnvironmentManager.setOnboardingCompleted(true)
        onboardingStep = .ready
        showOnboarding = false
        inlineMessage = "Oracle Controller is ready."
    }

    func openAccessibilitySettings() {
        productEnvironmentManager.openSystemSettingsForAccessibility()
    }

    func openScreenRecordingSettings() {
        productEnvironmentManager.openSystemSettingsForScreenRecording()
    }

    func installVisionBootstrap() async {
        do {
            isBusy = true
            defer { isBusy = false }
            productStatus = try productEnvironmentManager.installVisionBootstrap(repair: false)
            await refreshHealth()
            inlineMessage = "Vision bootstrap installed. Enable the sidecar when you are ready."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repairVisionBootstrap() async {
        do {
            isBusy = true
            defer { isBusy = false }
            productStatus = try productEnvironmentManager.installVisionBootstrap(repair: true)
            await refreshHealth()
            inlineMessage = "Vision bootstrap repaired."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealDataFolder() {
        productEnvironmentManager.revealDataFolder()
    }

    func revealLogsFolder() {
        productEnvironmentManager.openLogsFolder()
    }

    func openHelp() {
        productEnvironmentManager.openHelp()
    }

    func openReleaseNotes() {
        productEnvironmentManager.openReleaseNotes()
    }

    func showAboutPanel() {
        let buildVersion = productStatus?.buildVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "Development"
        let buildNumber = productStatus?.buildNumber
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? buildVersion

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Oracle Controller",
            .applicationVersion: buildVersion,
            .version: buildNumber,
            .credits: "Safe local macOS operator and engineering console for Oracle OS.",
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func exportDiagnostics() {
        do {
            let destination = try productEnvironmentManager.exportDiagnostics(
                health: health,
                session: session,
                snapshot: snapshot,
                approvals: approvalQueue,
                traceDetail: traceDetail,
                recipes: recipes,
                productStatus: productStatus,
                diagnostics: diagnostics
            )
            inlineMessage = "Exported diagnostics to \(destination.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetControllerData() {
        let alert = NSAlert()
        alert.messageText = "Reset Oracle Controller data?"
        alert.informativeText = "This removes local traces, approvals, exports, packaged vision bootstrap files, and seeded runtime data under Application Support."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            productStatus = try productEnvironmentManager.resetAllData()
            productEnvironmentManager.setOnboardingCompleted(false)
            showOnboarding = true
            onboardingStep = .welcome
            inlineMessage = "Controller data reset."
            Task {
                await refreshHealth()
                await loadRecipes()
                await loadTraceSessions()
                await loadApprovalRequests()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
