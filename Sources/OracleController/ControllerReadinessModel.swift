import Foundation
import OracleControllerShared

enum ControllerReadinessLevel: String, Equatable {
    case loading
    case ready
    case review
    case setupRequired
    case attention
}

enum ControllerReadinessAction: Equatable {
    case retryHost
    case openAccessibilitySettings
    case openScreenRecordingSettings
    case reviewHealth
    case reviewApprovals
    case installVision
    case openControl
    case refreshMissionControl
}

struct ControllerReadinessTask: Identifiable, Equatable {
    enum State: String, Equatable {
        case complete
        case actionRequired
        case attention
        case pending
        case optional

        var isBlocking: Bool {
            switch self {
            case .complete, .optional:
                return false
            case .actionRequired, .attention, .pending:
                return true
            }
        }

        var isOptional: Bool {
            self == .optional
        }

        var countsAsComplete: Bool {
            self == .complete
        }
    }

    let id: String
    let title: String
    let detail: String
    let state: State
    let actionTitle: String?
    let action: ControllerReadinessAction?
}

struct ControllerReadinessSummary: Equatable {
    let level: ControllerReadinessLevel
    let title: String
    let detail: String
    let statusLabel: String
    let primaryActionTitle: String
    let primaryAction: ControllerReadinessAction
    let checklist: [ControllerReadinessTask]

    var blockingTasks: [ControllerReadinessTask] {
        checklist.filter { $0.state.isBlocking }
    }

    var coreTasks: [ControllerReadinessTask] {
        checklist.filter { !$0.state.isOptional }
    }

    var completionSummary: String {
        guard !coreTasks.isEmpty else {
            return "Waiting for runtime status."
        }

        let completed = coreTasks.filter { $0.state.countsAsComplete }.count
        return "\(completed) of \(coreTasks.count) core checks clear"
    }
}

extension ControllerStore {
    var readinessSummary: ControllerReadinessSummary {
        let hostTask = hostBridgeTask
        let accessibilityTask = permissionTask(
            permissionID: "accessibility",
            fallbackTitle: "Accessibility",
            fallbackDetail: "Accessibility unlocks app inspection and supervised control.",
            actionTitle: "Open Accessibility",
            action: .openAccessibilitySettings
        )
        let screenRecordingTask = permissionTask(
            permissionID: "screen-recording",
            fallbackTitle: "Screen Recording",
            fallbackDetail:
                "Screen Recording powers screenshots and screenshot-backed diagnostics.",
            actionTitle: "Open Screen Recording",
            action: .openScreenRecordingSettings
        )
        let storageTask = localStorageTask
        let approvalsTask = approvalsTask
        let visionTask = visionTask
        let copilotTask = copilotTask
        let checklist = [
            hostTask,
            accessibilityTask,
            screenRecordingTask,
            storageTask,
            approvalsTask,
            visionTask,
            copilotTask,
        ]

        if hostConnection.requiresAttention {
            return ControllerReadinessSummary(
                level: .attention,
                title: "Reconnect the host bridge before you continue.",
                detail: hostConnection.detailText,
                statusLabel: "Host Attention",
                primaryActionTitle: "Retry Host",
                primaryAction: .retryHost,
                checklist: checklist
            )
        }

        if hostConnection.phase == .launching || (!isLoaded && hostConnection.phase == .idle) {
            return ControllerReadinessSummary(
                level: .loading,
                title: "Collecting live readiness from the local controller.",
                detail: "The app is still building its first host and runtime snapshot.",
                statusLabel: "Refreshing",
                primaryActionTitle: "Refresh Mission Control",
                primaryAction: .refreshMissionControl,
                checklist: checklist
            )
        }

        if accessibilityTask.state == .pending
            || screenRecordingTask.state == .pending
            || storageTask.state == .pending
        {
            return ControllerReadinessSummary(
                level: .loading,
                title: "Waiting for the full readiness snapshot.",
                detail:
                    "Permissions, storage, and runtime status will settle after the next successful health refresh.",
                statusLabel: "Refreshing",
                primaryActionTitle: "Refresh Mission Control",
                primaryAction: .refreshMissionControl,
                checklist: checklist
            )
        }

        if accessibilityTask.state == .actionRequired {
            return ControllerReadinessSummary(
                level: .setupRequired,
                title: "Grant Accessibility to unlock supervised app control.",
                detail: accessibilityTask.detail,
                statusLabel: "Finish Setup",
                primaryActionTitle: accessibilityTask.actionTitle ?? "Open Accessibility",
                primaryAction: .openAccessibilitySettings,
                checklist: checklist
            )
        }

        if screenRecordingTask.state == .actionRequired {
            return ControllerReadinessSummary(
                level: .setupRequired,
                title: "Grant Screen Recording to restore live snapshots and diagnostics.",
                detail: screenRecordingTask.detail,
                statusLabel: "Finish Setup",
                primaryActionTitle: screenRecordingTask.actionTitle ?? "Open Screen Recording",
                primaryAction: .openScreenRecordingSettings,
                checklist: checklist
            )
        }

        if storageTask.state == .attention {
            return ControllerReadinessSummary(
                level: .attention,
                title: "Fix local storage before trusting fresh controller evidence.",
                detail: storageTask.detail,
                statusLabel: "Storage Attention",
                primaryActionTitle: "Review Health",
                primaryAction: .reviewHealth,
                checklist: checklist
            )
        }

        if approvalsTask.state == .pending {
            return ControllerReadinessSummary(
                level: .review,
                title: "Pending approvals are the main thing blocking forward progress.",
                detail: approvalsTask.detail,
                statusLabel: "Review Approvals",
                primaryActionTitle: "Open Control",
                primaryAction: .reviewApprovals,
                checklist: checklist
            )
        }

        return ControllerReadinessSummary(
            level: .ready,
            title: "The controller is ready for supervised operator work.",
            detail: "Core permissions, host connectivity, storage, and approval state are clear.",
            statusLabel: "Operator Ready",
            primaryActionTitle: "Open Control",
            primaryAction: .openControl,
            checklist: checklist
        )
    }

    func performReadinessAction(_ action: ControllerReadinessAction) {
        switch action {
        case .retryHost:
            Task { await retryHostConnection() }
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .openScreenRecordingSettings:
            openScreenRecordingSettings()
        case .reviewHealth:
            selectedSection = .health
        case .reviewApprovals, .openControl:
            selectedSection = .control
        case .installVision:
            Task { await installVisionBootstrap() }
        case .refreshMissionControl:
            Task { await refreshMissionControl() }
        }
    }

    private var currentHealthSnapshot: HealthStatus? {
        missionControl?.health ?? health
    }

    private var currentProviderStatus: ChatProviderStatus? {
        chatProviderStatus ?? missionControl?.providerStatus
    }

    private var hostBridgeTask: ControllerReadinessTask {
        switch hostConnection.phase {
        case .connected:
            return ControllerReadinessTask(
                id: "host-bridge",
                title: "Host Bridge",
                detail: hostConnection.detailText,
                state: .complete,
                actionTitle: nil,
                action: nil
            )
        case .launching, .idle:
            return ControllerReadinessTask(
                id: "host-bridge",
                title: "Host Bridge",
                detail: hostConnection.detailText,
                state: .pending,
                actionTitle: nil,
                action: nil
            )
        case .disconnected, .failed:
            return ControllerReadinessTask(
                id: "host-bridge",
                title: "Host Bridge",
                detail: hostConnection.detailText,
                state: .attention,
                actionTitle: "Retry Host",
                action: .retryHost
            )
        }
    }

    private func permissionTask(
        permissionID: String,
        fallbackTitle: String,
        fallbackDetail: String,
        actionTitle: String,
        action: ControllerReadinessAction
    ) -> ControllerReadinessTask {
        guard let health = currentHealthSnapshot else {
            return ControllerReadinessTask(
                id: permissionID,
                title: fallbackTitle,
                detail: "Waiting for the controller to report this permission.",
                state: .pending,
                actionTitle: nil,
                action: nil
            )
        }

        guard let permission = health.permissions.first(where: { $0.id == permissionID }) else {
            return ControllerReadinessTask(
                id: permissionID,
                title: fallbackTitle,
                detail: "Waiting for the controller to report this permission.",
                state: .pending,
                actionTitle: nil,
                action: nil
            )
        }

        return ControllerReadinessTask(
            id: permissionID,
            title: permission.title,
            detail: permission.detail ?? fallbackDetail,
            state: permission.granted ? .complete : .actionRequired,
            actionTitle: permission.granted ? nil : actionTitle,
            action: permission.granted ? nil : action
        )
    }

    private var localStorageTask: ControllerReadinessTask {
        guard let health = currentHealthSnapshot else {
            return ControllerReadinessTask(
                id: "local-storage",
                title: "Local Storage",
                detail: "Waiting for writable controller paths to be checked.",
                state: .pending,
                actionTitle: nil,
                action: nil
            )
        }

        if health.storageReady {
            return ControllerReadinessTask(
                id: "local-storage",
                title: "Local Storage",
                detail:
                    "Traces, approvals, recipes, logs, and graph data can all be written locally.",
                state: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        let failingLocations = health.storageIssues.map(\.title).joined(separator: ", ")
        return ControllerReadinessTask(
            id: "local-storage",
            title: "Local Storage",
            detail: "Write access is blocked for: \(failingLocations).",
            state: .attention,
            actionTitle: "Review Health",
            action: .reviewHealth
        )
    }

    private var approvalsTask: ControllerReadinessTask {
        let pendingApprovals = missionControl?.approvals.count ?? approvalQueue.count
        if pendingApprovals == 0 {
            return ControllerReadinessTask(
                id: "approvals",
                title: "Pending Approvals",
                detail: "No risky work is waiting for operator review.",
                state: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        return ControllerReadinessTask(
            id: "approvals",
            title: "Pending Approvals",
            detail:
                "\(pendingApprovals) action\(pendingApprovals == 1 ? "" : "s") need operator review before they can continue.",
            state: .pending,
            actionTitle: "Open Control",
            action: .reviewApprovals
        )
    }

    private var visionTask: ControllerReadinessTask {
        let health = currentHealthSnapshot
        let visionInstalled = productStatus?.visionInstalled == true
        let bundledAssetsAvailable =
            productStatus?.bundledVisionBootstrapAvailable == true
            || health?.bundledVisionBootstrapAvailable == true

        if health?.visionSidecarRunning == true {
            return ControllerReadinessTask(
                id: "vision",
                title: "Vision Sidecar",
                detail: "Optional screen parsing is installed and currently available.",
                state: .complete,
                actionTitle: nil,
                action: nil
            )
        }

        if visionInstalled {
            return ControllerReadinessTask(
                id: "vision",
                title: "Vision Sidecar",
                detail:
                    "Optional vision support is installed but currently offline. Core Accessibility control still works.",
                state: .attention,
                actionTitle: nil,
                action: nil
            )
        }

        return ControllerReadinessTask(
            id: "vision",
            title: "Vision Sidecar",
            detail: bundledAssetsAvailable
                ? "Optional vision support is available if you want screenshot-backed enrichment."
                : "Optional vision support is not installed, and core Accessibility control remains available.",
            state: .optional,
            actionTitle: bundledAssetsAvailable ? "Install Vision" : nil,
            action: bundledAssetsAvailable ? .installVision : nil
        )
    }

    private var copilotTask: ControllerReadinessTask {
        if let providerStatus = currentProviderStatus {
            switch providerStatus.state {
            case .ready:
                return ControllerReadinessTask(
                    id: "copilot",
                    title: "Copilot Guidance",
                    detail: providerStatus.detail,
                    state: .complete,
                    actionTitle: nil,
                    action: nil
                )
            case .setupRequired:
                return ControllerReadinessTask(
                    id: "copilot",
                    title: "Copilot Guidance",
                    detail: providerStatus.detail,
                    state: providerStatus.configured ? .attention : .optional,
                    actionTitle: nil,
                    action: nil
                )
            case .unavailable:
                return ControllerReadinessTask(
                    id: "copilot",
                    title: "Copilot Guidance",
                    detail: providerStatus.detail,
                    state: providerStatus.configured ? .attention : .optional,
                    actionTitle: nil,
                    action: nil
                )
            }
        }

        return ControllerReadinessTask(
            id: "copilot",
            title: "Copilot Guidance",
            detail: currentHealthSnapshot?.claudeConfigured == true
                ? "Copilot is configured, but the current provider status has not arrived yet."
                : "Copilot remains optional until you configure a local or OpenAI-compatible backend.",
            state: currentHealthSnapshot?.claudeConfigured == true ? .attention : .optional,
            actionTitle: nil,
            action: nil
        )
    }
}
