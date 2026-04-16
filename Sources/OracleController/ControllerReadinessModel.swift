import Foundation
import OracleControllerShared
import SwiftUI

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

enum ControllerSummaryTone: String, Equatable {
    case neutral
    case good
    case warning
    case danger

    var badgeTone: StatusBadge.Tone {
        switch self {
        case .neutral:
            return .neutral
        case .good:
            return .good
        case .warning:
            return .warning
        case .danger:
            return .danger
        }
    }

    var rowFill: Color {
        switch self {
        case .neutral:
            return ControllerTheme.panelRaised.opacity(0.92)
        case .good:
            return ControllerTheme.success.opacity(0.08)
        case .warning:
            return ControllerTheme.warning.opacity(0.1)
        case .danger:
            return ControllerTheme.danger.opacity(0.09)
        }
    }

    fileprivate var rank: Int {
        switch self {
        case .danger:
            return 3
        case .warning:
            return 2
        case .neutral:
            return 1
        case .good:
            return 0
        }
    }
}

struct ControllerActionSummary: Identifiable, Equatable {
    let result: ActionRunResult
    let tone: ControllerSummaryTone
    let outcomeTitle: String
    let summary: String
    let executionDetail: String
    let contextDetail: String?

    var id: UUID { result.id }
    var title: String { result.request.displayTitle }
    var statusLabel: String { result.statusLabel }
    var elapsedMs: Double { result.elapsedMs }
}

struct ControllerApprovalReviewSummary: Equatable {
    let tone: ControllerSummaryTone
    let title: String
    let detail: String
    let statusLabel: String
    let emptyStateTitle: String
    let emptyStateMessage: String
}

private enum ControllerDiagnosticsIssueCategory: Int, Equatable {
    case runtimeEvidence
    case architecture
    case promotions
    case recovery
    case graph
    case workflow
    case repository
}

enum ControllerDiagnosticsIssueTarget: Equatable {
    case graphEdge(String)
    case workflow(String)
    case architectureFinding(String)
}

struct ControllerDiagnosticsIssue: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let sourceLabel: String
    let tone: ControllerSummaryTone
    let target: ControllerDiagnosticsIssueTarget?
    fileprivate let category: ControllerDiagnosticsIssueCategory

    var statusLabel: String {
        switch tone {
        case .danger:
            return "Investigate"
        case .warning:
            return "Watch"
        case .neutral:
            return "Advisory"
        case .good:
            return "Clear"
        }
    }

    var actionTitle: String? {
        switch target {
        case .graphEdge:
            return "Open Edge"
        case .workflow:
            return "Open Workflow"
        case .architectureFinding:
            return "Open Finding"
        case nil:
            return nil
        }
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

    var recentActionSummaries: [ControllerActionSummary] {
        recentActions.map(actionSummary(for:))
    }

    var currentActionSummary: ControllerActionSummary? {
        currentActionResult.map(actionSummary(for:))
    }

    var activeApprovalRows: [ApprovalRow] {
        approvalRows.filter { row in
            switch row.phase {
            case .pending, .submitting:
                return true
            case .resolved:
                return false
            }
        }
    }

    var approvalReviewSummary: ControllerApprovalReviewSummary {
        let actionableRows = activeApprovalRows
        let pendingCount = actionableRows.filter { row in
            if case .pending = row.phase {
                return true
            }
            return false
        }.count
        let submittingCount = actionableRows.count - pendingCount

        if submittingCount > 0 {
            return ControllerApprovalReviewSummary(
                tone: .neutral,
                title: submittingCount == 1
                    ? "Submitting an approval decision."
                    : "Submitting \(submittingCount) approval decisions.",
                detail: pendingCount == 0
                    ? "Recent decisions move into the action feed once the runtime responds."
                    : "\(pendingCount) other action\(pendingCount == 1 ? "" : "s") still wait for operator review.",
                statusLabel: "Updating",
                emptyStateTitle: "Approval Decision In Flight",
                emptyStateMessage:
                    "Recent decisions move into the action feed once the runtime responds."
            )
        }

        if pendingCount > 0 {
            return ControllerApprovalReviewSummary(
                tone: .warning,
                title: pendingCount == 1
                    ? "1 action still needs operator review."
                    : "\(pendingCount) actions still need operator review.",
                detail:
                    "Only paused awaiting-approval work stays here. Rejections and policy blocks move into the action feed.",
                statusLabel: "Needs Review",
                emptyStateTitle: "No Pending Approvals",
                emptyStateMessage:
                    "Only paused awaiting-approval work stays here. Rejections and policy blocks move into the action feed."
            )
        }

        if !recentApprovalResolutions.isEmpty {
            return ControllerApprovalReviewSummary(
                tone: .good,
                title: "Approval queue is clear.",
                detail: "Recent approval decisions are now reflected in the action feed.",
                statusLabel: "Clear",
                emptyStateTitle: "No Pending Approvals",
                emptyStateMessage:
                    "Recent approval decisions are now reflected in the action feed. Only work still waiting for review stays here."
            )
        }

        return ControllerApprovalReviewSummary(
            tone: .good,
            title: "Approval queue is clear.",
            detail:
                "Only paused awaiting-approval work stays here when the runtime needs a decision.",
            statusLabel: "Clear",
            emptyStateTitle: "No Pending Approvals",
            emptyStateMessage:
                "Only paused awaiting-approval work stays here. Rejections and policy blocks move into the action feed."
        )
    }

    var diagnosticsInvestigationItems: [ControllerDiagnosticsIssue] {
        guard let diagnostics else {
            return []
        }

        var issues: [ControllerDiagnosticsIssue] = []

        if let issue = hostDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = browserDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = architectureDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = promotionsDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = recoveryDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = graphDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = workflowDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }
        if let issue = repositoryDiagnosticsIssue(from: diagnostics) {
            issues.append(issue)
        }

        return Array(
            issues
                .sorted(by: compareDiagnosticsIssues)
                .prefix(5)
        )
    }

    func performDiagnosticsInvestigation(_ issue: ControllerDiagnosticsIssue) {
        clearDiagnosticsSelections()

        switch issue.target {
        case .graphEdge(let id):
            selectedGraphEdgeID = id
        case .workflow(let id):
            selectedWorkflowID = id
        case .architectureFinding(let id):
            selectedArchitectureFindingID = id
        case nil:
            break
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

    private func actionSummary(for result: ActionRunResult) -> ControllerActionSummary {
        ControllerActionSummary(
            result: result,
            tone: actionTone(for: result),
            outcomeTitle: actionOutcomeTitle(for: result),
            summary: result.summaryText,
            executionDetail: result.executionPathSummary,
            contextDetail: actionContextDetail(for: result)
        )
    }

    private func actionTone(for result: ActionRunResult) -> ControllerSummaryTone {
        switch result.disposition {
        case .awaitingApproval:
            return .warning
        case .rejected, .blockedByPolicy, .failed:
            return .danger
        case .verifiedExecution:
            return .good
        case .observed:
            return .neutral
        case .partialSuccess:
            return .warning
        }
    }

    private func actionOutcomeTitle(for result: ActionRunResult) -> String {
        switch result.disposition {
        case .awaitingApproval:
            return "Waiting For Operator Approval"
        case .rejected:
            return "Approval Rejected"
        case .blockedByPolicy:
            return "Blocked By Policy"
        case .verifiedExecution:
            return "Verified Runtime Path"
        case .observed:
            return result.request.kind == .wait ? "Observed Wait Result" : "Observed Local Result"
        case .partialSuccess:
            return "Partial Verified Outcome"
        case .failed:
            return result.executedThroughExecutor ? "Verified Runtime Failure" : "Local Failure"
        }
    }

    private func actionContextDetail(for result: ActionRunResult) -> String? {
        if let approvalRequestID = result.approvalRequestID,
            !approvalRequestID.isEmpty
        {
            switch result.disposition {
            case .awaitingApproval:
                return "Approval request \(approvalRequestID) is still waiting for operator review."
            case .rejected:
                return
                    "Approval request \(approvalRequestID) was rejected before the runtime could continue."
            default:
                return "Linked to approval request \(approvalRequestID)."
            }
        }

        if result.blockedByPolicy,
            let policyMode = result.policyMode,
            !policyMode.isEmpty
        {
            return "The current policy mode is \(policyMode)."
        }

        if let failureClass = result.failureClass,
            failureClass != "partial_success",
            failureClass != "approval_rejected"
        {
            return "Failure class: \(failureClass)."
        }

        return nil
    }

    private func clearDiagnosticsSelections() {
        selectedGraphEdgeID = nil
        selectedWorkflowID = nil
        selectedExperimentID = nil
        selectedProjectMemoryID = nil
        selectedArchitectureFindingID = nil
    }

    private func compareDiagnosticsIssues(
        _ lhs: ControllerDiagnosticsIssue,
        _ rhs: ControllerDiagnosticsIssue
    ) -> Bool {
        if lhs.tone.rank != rhs.tone.rank {
            return lhs.tone.rank > rhs.tone.rank
        }
        if lhs.category.rawValue != rhs.category.rawValue {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        return lhs.title < rhs.title
    }

    private func hostDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        guard let host = diagnostics.host else {
            return ControllerDiagnosticsIssue(
                id: "diagnostics-host-missing",
                title: "Host evidence is missing",
                detail:
                    "Capture a fresh host snapshot before relying on app, window, and permission diagnostics.",
                sourceLabel: "Host",
                tone: .danger,
                target: nil,
                category: .runtimeEvidence
            )
        }

        let missingPermissions = [
            host.accessibilityGranted ? nil : "Accessibility",
            host.screenRecordingGranted ? nil : "Screen Recording",
        ].compactMap { $0 }

        guard !missingPermissions.isEmpty else {
            return nil
        }

        return ControllerDiagnosticsIssue(
            id: "diagnostics-host-permissions",
            title: "Host evidence is incomplete",
            detail:
                "\(missingPermissions.joined(separator: " and ")) still needs permission before host diagnostics are fully trustworthy.",
            sourceLabel: "Host",
            tone: .danger,
            target: nil,
            category: .runtimeEvidence
        )
    }

    private func browserDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        if let browser = diagnostics.browser,
            browser.available == false
        {
            return ControllerDiagnosticsIssue(
                id: "diagnostics-browser-unavailable",
                title: "Browser evidence is unavailable",
                detail:
                    "A browser snapshot exists, but DOM-backed inspection is currently unavailable for this capture.",
                sourceLabel: "Browser",
                tone: .warning,
                target: nil,
                category: .runtimeEvidence
            )
        }

        guard diagnostics.browser == nil,
            isLikelyBrowserContext(activeApplication: diagnostics.host?.activeApplication)
        else {
            return nil
        }

        return ControllerDiagnosticsIssue(
            id: "diagnostics-browser-missing",
            title: "Browser evidence is missing",
            detail:
                "The active app looks browser-based, but no reduced browser snapshot was captured for this run.",
            sourceLabel: "Browser",
            tone: .warning,
            target: nil,
            category: .runtimeEvidence
        )
    }

    private func architectureDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        let candidates = diagnostics.architectureFindings.filter { finding in
            finding.severity.caseInsensitiveCompare("critical") == .orderedSame
                || finding.riskScore >= 0.75
        }

        guard let finding = candidates.sorted(by: compareArchitectureFindings).first else {
            return nil
        }

        let tone: ControllerSummaryTone =
            finding.severity.caseInsensitiveCompare("critical") == .orderedSame
                || finding.riskScore >= 0.9
            ? .danger : .warning

        return ControllerDiagnosticsIssue(
            id: "diagnostics-architecture-\(finding.id)",
            title: "Architecture risk needs review",
            detail:
                "\(finding.title) carries a risk score of \(String(format: "%.2f", finding.riskScore)) across \(finding.occurrences) occurrence\(finding.occurrences == 1 ? "" : "s").",
            sourceLabel: "Architecture",
            tone: tone,
            target: .architectureFinding(finding.id),
            category: .architecture
        )
    }

    private func promotionsDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        guard diagnostics.graph.promotionsFrozen else {
            return nil
        }

        return ControllerDiagnosticsIssue(
            id: "diagnostics-promotions-frozen",
            title: "Learning promotions are paused",
            detail: diagnostics.graph.promotionEligibleCount > 0
                ? "\(diagnostics.graph.promotionEligibleCount) graph transition\(diagnostics.graph.promotionEligibleCount == 1 ? " is" : "s are") eligible but cannot promote while freezes are active."
                : "Promotions are frozen, so fresh graph evidence cannot move into the stable tier yet.",
            sourceLabel: "Graph",
            tone: .warning,
            target: nil,
            category: .promotions
        )
    }

    private func recoveryDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        let candidates = diagnostics.recovery.strategies.filter { strategy in
            strategy.attempts > 0
                && Double(strategy.successes) / Double(strategy.attempts) < 0.5
        }

        guard let strategy = candidates.sorted(by: compareRecoveryStrategies).first else {
            return nil
        }

        let successRate = Double(strategy.successes) / Double(strategy.attempts)
        let topFailure = strategy.failureHistogram.max { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            return lhs.key > rhs.key
        }?.key

        return ControllerDiagnosticsIssue(
            id: "diagnostics-recovery-\(strategy.id)",
            title: "Recovery performance needs review",
            detail:
                "\(strategy.id) succeeds \(strategy.successes) of \(strategy.attempts) times (\(Int(successRate * 100))%)."
                + (topFailure.map { " Most common failure: \($0)." } ?? ""),
            sourceLabel: "Recovery",
            tone: strategy.attempts >= 4 && successRate < 0.25 ? .danger : .warning,
            target: nil,
            category: .recovery
        )
    }

    private func graphDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        let edges =
            diagnostics.graph.recoveryEdges
            + diagnostics.graph.candidateEdges
            + diagnostics.graph.stableEdges
        let candidates = edges.filter { edge in
            edge.attempts >= 2
                && (edge.recoveryTagged || edge.successRate < 0.6 || edge.targetAmbiguityRate > 0.4)
        }

        guard let edge = candidates.sorted(by: compareGraphEdges).first else {
            return nil
        }

        let ambiguityText =
            edge.targetAmbiguityRate > 0.4
            ? " Target ambiguity is \(Int(edge.targetAmbiguityRate * 100))%."
            : ""

        return ControllerDiagnosticsIssue(
            id: "diagnostics-graph-\(edge.id)",
            title: "A graph transition is unreliable",
            detail:
                "\(edge.actionContractID) succeeds \(Int(edge.successRate * 100))% of the time across \(edge.attempts) attempts.\(ambiguityText)",
            sourceLabel: "Graph",
            tone: edge.recoveryTagged && edge.successRate < 0.4 ? .danger : .warning,
            target: .graphEdge(edge.id),
            category: .graph
        )
    }

    private func workflowDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        guard let workflow = diagnostics.workflows.first(where: { $0.stale }) else {
            return nil
        }

        return ControllerDiagnosticsIssue(
            id: "diagnostics-workflow-\(workflow.id)",
            title: "Workflow replay guidance looks stale",
            detail:
                "\(workflow.goalPattern) is marked stale and may need replay validation before you trust it.",
            sourceLabel: "Workflow",
            tone: workflow.promotionStatus == "promoted" ? .warning : .neutral,
            target: .workflow(workflow.id),
            category: .workflow
        )
    }

    private func repositoryDiagnosticsIssue(
        from diagnostics: ControllerDiagnosticsSnapshot
    ) -> ControllerDiagnosticsIssue? {
        guard let index = diagnostics.repositoryIndexes.first(where: { $0.isGitDirty }) else {
            return nil
        }

        let workspaceName = URL(fileURLWithPath: index.workspaceRoot).lastPathComponent
        let branchDetail = index.activeBranch.map { " on \($0)" } ?? ""

        return ControllerDiagnosticsIssue(
            id: "diagnostics-repository-\(index.id)",
            title: "Repository intelligence may be stale",
            detail:
                "\(workspaceName) has uncommitted changes\(branchDetail), so index-backed diagnostics are advisory until the workspace settles.",
            sourceLabel: "Repository",
            tone: .neutral,
            target: nil,
            category: .repository
        )
    }

    private func isLikelyBrowserContext(activeApplication: String?) -> Bool {
        guard let activeApplication else {
            return false
        }

        let name = activeApplication.lowercased()
        return name.contains("safari")
            || name.contains("chrome")
            || name.contains("firefox")
            || name.contains("brave")
            || name.contains("arc")
            || name.contains("edge")
    }

    private func compareArchitectureFindings(
        _ lhs: ControllerArchitectureFindingDiagnostics,
        _ rhs: ControllerArchitectureFindingDiagnostics
    ) -> Bool {
        let lhsCritical = lhs.severity.caseInsensitiveCompare("critical") == .orderedSame
        let rhsCritical = rhs.severity.caseInsensitiveCompare("critical") == .orderedSame

        if lhsCritical != rhsCritical {
            return lhsCritical
        }
        if lhs.riskScore != rhs.riskScore {
            return lhs.riskScore > rhs.riskScore
        }
        if lhs.occurrences != rhs.occurrences {
            return lhs.occurrences > rhs.occurrences
        }
        return lhs.title < rhs.title
    }

    private func compareRecoveryStrategies(
        _ lhs: ControllerRecoveryStrategyDiagnostics,
        _ rhs: ControllerRecoveryStrategyDiagnostics
    ) -> Bool {
        let lhsSuccessRate = lhs.attempts == 0 ? 1.0 : Double(lhs.successes) / Double(lhs.attempts)
        let rhsSuccessRate = rhs.attempts == 0 ? 1.0 : Double(rhs.successes) / Double(rhs.attempts)

        if lhsSuccessRate != rhsSuccessRate {
            return lhsSuccessRate < rhsSuccessRate
        }
        if lhs.attempts != rhs.attempts {
            return lhs.attempts > rhs.attempts
        }
        return lhs.id < rhs.id
    }

    private func compareGraphEdges(
        _ lhs: ControllerGraphEdgeDiagnostics,
        _ rhs: ControllerGraphEdgeDiagnostics
    ) -> Bool {
        if lhs.recoveryTagged != rhs.recoveryTagged {
            return lhs.recoveryTagged
        }
        if lhs.successRate != rhs.successRate {
            return lhs.successRate < rhs.successRate
        }
        if lhs.targetAmbiguityRate != rhs.targetAmbiguityRate {
            return lhs.targetAmbiguityRate > rhs.targetAmbiguityRate
        }
        if lhs.attempts != rhs.attempts {
            return lhs.attempts > rhs.attempts
        }
        return lhs.actionContractID < rhs.actionContractID
    }
}
