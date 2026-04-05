import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ControllerLayoutSettings {
    private enum Key {
        static let sidebarWidth = "oracleController.layout.sidebarWidth"
        static let inspectorWidth = "oracleController.layout.inspectorWidth"
        static let railWidth = "oracleController.layout.railWidth"
        static let utilityWidth = "oracleController.layout.utilityWidth"
        static let workspacePadding = "oracleController.layout.workspacePadding"
    }

    private let defaults: UserDefaults

    var sidebarWidth: Double {
        didSet { persist(sidebarWidth, for: Key.sidebarWidth) }
    }

    var inspectorWidth: Double {
        didSet { persist(inspectorWidth, for: Key.inspectorWidth) }
    }

    var railWidth: Double {
        didSet { persist(railWidth, for: Key.railWidth) }
    }

    var utilityWidth: Double {
        didSet { persist(utilityWidth, for: Key.utilityWidth) }
    }

    var workspacePadding: Double {
        didSet { persist(workspacePadding, for: Key.workspacePadding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sidebarWidth = defaults.object(forKey: Key.sidebarWidth) as? Double ?? 380
        self.inspectorWidth = defaults.object(forKey: Key.inspectorWidth) as? Double ?? 470
        self.railWidth = defaults.object(forKey: Key.railWidth) as? Double ?? 380
        self.utilityWidth = defaults.object(forKey: Key.utilityWidth) as? Double ?? 420
        self.workspacePadding = defaults.object(forKey: Key.workspacePadding) as? Double ?? 20
    }

    var sidebarColumnWidth: CGFloat { CGFloat(sidebarWidth) }
    var inspectorColumnWidth: CGFloat { CGFloat(inspectorWidth) }
    var railPanelWidth: CGFloat { CGFloat(railWidth) }
    var utilityPanelWidth: CGFloat { CGFloat(utilityWidth) }
    var workspacePaddingValue: CGFloat { CGFloat(workspacePadding) }
    var stackSpacing: CGFloat { CGFloat(max(14, workspacePadding - 2)) }
    var controlSpacing: CGFloat { CGFloat(max(10, workspacePadding - 8)) }
    var minimumWindowWidth: CGFloat {
        max(1440, sidebarColumnWidth + inspectorColumnWidth + utilityPanelWidth + 340)
    }

    func resetToDefaults() {
        sidebarWidth = 380
        inspectorWidth = 470
        railWidth = 380
        utilityWidth = 420
        workspacePadding = 20
    }

    private func persist(_ value: Double, for key: String) {
        defaults.set(value, forKey: key)
    }
}

struct ControllerLayoutEditor: View {
    @Environment(ControllerLayoutSettings.self) private var layout
    var compact = false

    var body: some View {
        @Bindable var layout = layout

        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            if !compact {
                Text("Make the navigation, dock, and workspace rails fit how you actually use the controller. Changes apply immediately and persist between launches.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ControllerLayoutSlider(
                title: "Sidebar width",
                detail: "Left navigation and section list",
                value: $layout.sidebarWidth,
                range: 320...520
            )

            ControllerLayoutSlider(
                title: "Inspector width",
                detail: "Copilot and right-side inspector dock",
                value: $layout.inspectorWidth,
                range: 420...760
            )

            ControllerLayoutSlider(
                title: "Rail width",
                detail: "Recipe library, trace sessions, alerts, and timelines",
                value: $layout.railWidth,
                range: 320...480
            )

            ControllerLayoutSlider(
                title: "Utility width",
                detail: "Manual action composer and secondary side panels",
                value: $layout.utilityWidth,
                range: 360...560
            )

            ControllerLayoutSlider(
                title: "Workspace padding",
                detail: "Internal spacing around cards and columns",
                value: $layout.workspacePadding,
                range: 16...32,
                step: 1
            )

            HStack {
                Button("Reset Layout") {
                    layout.resetToDefaults()
                }
                .buttonStyle(ControllerSecondaryButtonStyle())

                Spacer()

                Text("Live and persistent")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ControllerTheme.muted)
            }
        }
    }
}

private struct ControllerLayoutSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ControllerTheme.ink)
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                }

                Spacer()

                Text("\(Int(value))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ControllerTheme.muted)
            }

            Slider(value: $value, in: range, step: step)
                .tint(ControllerTheme.accent)
        }
    }
}