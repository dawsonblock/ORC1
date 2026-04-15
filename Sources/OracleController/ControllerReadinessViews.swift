import SwiftUI

struct ControllerReadinessSummaryContent: View {
    @Bindable var store: ControllerStore
    var taskLimit: Int? = nil
    var showsPrimaryAction = true
    var showsCompletion = true
    var showsOptionalTasks = true

    private var summary: ControllerReadinessSummary {
        store.readinessSummary
    }

    private var visibleTasks: [ControllerReadinessTask] {
        let tasks =
            showsOptionalTasks
            ? summary.checklist : summary.checklist.filter { !$0.state.isOptional }
        guard let taskLimit else {
            return tasks
        }
        return Array(tasks.prefix(taskLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ControllerTheme.ink)

                    Text(summary.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsCompletion {
                        Text(summary.completionSummary)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(ControllerTheme.muted)
                    }
                }

                Spacer(minLength: 12)

                StatusBadge(label: summary.statusLabel, tone: summary.level.badgeTone)
            }

            if showsPrimaryAction {
                HStack(spacing: 10) {
                    Button(summary.primaryActionTitle) {
                        store.performReadinessAction(summary.primaryAction)
                    }
                    .buttonStyle(ControllerPrimaryButtonStyle())

                    Text(blockingSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }

            ControllerReadinessTaskList(store: store, tasks: visibleTasks)
        }
    }

    private var blockingSummary: String {
        let blockingCount = summary.blockingTasks.count
        if blockingCount == 0 {
            return "All core checks are clear."
        }
        return "\(blockingCount) item\(blockingCount == 1 ? "" : "s") still needs attention."
    }
}

struct ControllerReadinessTaskList: View {
    @Bindable var store: ControllerStore
    let tasks: [ControllerReadinessTask]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(tasks) { task in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: task.state.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(task.state.badgeTone.color)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(ControllerTheme.ink)

                        Text(task.detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ControllerTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if let actionTitle = task.actionTitle,
                            let action = task.action
                        {
                            Button(actionTitle) {
                                store.performReadinessAction(action)
                            }
                            .buttonStyle(ControllerSecondaryButtonStyle())
                        }
                    }

                    Spacer(minLength: 12)

                    StatusBadge(label: task.state.badgeLabel, tone: task.state.badgeTone)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(task.state.rowFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(task.state.badgeTone.color.opacity(0.16), lineWidth: 1)
                        )
                )
            }
        }
    }
}

extension ControllerReadinessLevel {
    var badgeTone: StatusBadge.Tone {
        switch self {
        case .loading:
            return .neutral
        case .ready:
            return .good
        case .review, .setupRequired:
            return .warning
        case .attention:
            return .danger
        }
    }
}

extension ControllerReadinessTask.State {
    fileprivate var badgeTone: StatusBadge.Tone {
        switch self {
        case .complete:
            return .good
        case .actionRequired, .pending:
            return .warning
        case .attention:
            return .danger
        case .optional:
            return .neutral
        }
    }

    fileprivate var badgeLabel: String {
        switch self {
        case .complete:
            return "Ready"
        case .actionRequired:
            return "Action"
        case .attention:
            return "Attention"
        case .pending:
            return "Pending"
        case .optional:
            return "Optional"
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .complete:
            return "checkmark.circle.fill"
        case .actionRequired:
            return "slider.horizontal.3"
        case .attention:
            return "exclamationmark.triangle.fill"
        case .pending:
            return "clock.fill"
        case .optional:
            return "sparkles"
        }
    }

    fileprivate var rowFill: Color {
        switch self {
        case .complete:
            return ControllerTheme.success.opacity(0.08)
        case .actionRequired, .pending:
            return ControllerTheme.warning.opacity(0.10)
        case .attention:
            return ControllerTheme.danger.opacity(0.09)
        case .optional:
            return ControllerTheme.panelRaised.opacity(0.92)
        }
    }
}
