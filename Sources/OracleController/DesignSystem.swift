import AppKit
import SwiftUI
import OracleControllerShared

enum ControllerTheme {
    static let accent = Color(red: 0.10, green: 0.41, blue: 0.66)
    static let accentWarm = Color(red: 0.88, green: 0.54, blue: 0.22)
    static let accentCool = Color(red: 0.18, green: 0.64, blue: 0.57)
    static let canvas = Color(red: 0.95, green: 0.95, blue: 0.92)
    static let canvasTop = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let canvasBottom = Color(red: 0.87, green: 0.91, blue: 0.94)
    static let panel = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let panelRaised = Color(red: 0.99, green: 0.99, blue: 0.98)
    static let panelTint = Color(red: 0.93, green: 0.96, blue: 0.98)
    static let border = Color.black.opacity(0.08)
    static let borderStrong = Color.black.opacity(0.14)
    static let shadow = Color(red: 0.18, green: 0.21, blue: 0.24).opacity(0.14)
    static let ink = Color(red: 0.14, green: 0.18, blue: 0.22)
    static let muted = Color(red: 0.34, green: 0.39, blue: 0.45)
    static let success = Color(red: 0.17, green: 0.54, blue: 0.37)
    static let warning = Color(red: 0.83, green: 0.54, blue: 0.16)
    static let danger = Color(red: 0.74, green: 0.24, blue: 0.20)
}

struct ControllerBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ControllerTheme.canvasTop, ControllerTheme.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [ControllerTheme.accent.opacity(0.20), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            .offset(x: 120, y: -90)

            RadialGradient(
                colors: [ControllerTheme.accentWarm.opacity(0.14), .clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 360
            )
            .offset(x: -80, y: 140)
        }
        .ignoresSafeArea()
    }
}

enum PanelCardStyle {
    case standard
    case hero
    case muted
}

struct PanelCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let style: PanelCardStyle
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, style: PanelCardStyle = .standard, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .hero ? 18 : 14) {
            VStack(alignment: .leading, spacing: style == .hero ? 6 : 4) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(ControllerTheme.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: style == .hero ? 13 : 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ControllerTheme.muted)
                }
            }

            content
        }
        .padding(style == .hero ? 22 : 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(color: ControllerTheme.shadow, radius: style == .hero ? 26 : 18, y: style == .hero ? 14 : 8)
        )
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(accentFill)
                .frame(width: style == .hero ? 112 : 68, height: 5)
                .padding(.top, 12)
                .padding(.leading, style == .hero ? 22 : 18)
        }
    }

    private var titleFont: Font {
        switch style {
        case .standard:
            return .system(size: 15, weight: .semibold, design: .rounded)
        case .hero:
            return .system(size: 25, weight: .bold, design: .rounded)
        case .muted:
            return .system(size: 14, weight: .semibold, design: .rounded)
        }
    }

    private var backgroundFill: LinearGradient {
        switch style {
        case .standard:
            return LinearGradient(
                colors: [ControllerTheme.panelRaised.opacity(0.96), ControllerTheme.panel.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .hero:
            return LinearGradient(
                colors: [ControllerTheme.panelRaised, ControllerTheme.panelTint.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .muted:
            return LinearGradient(
                colors: [ControllerTheme.panel.opacity(0.92), ControllerTheme.panelTint.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        style == .hero ? ControllerTheme.borderStrong : ControllerTheme.border
    }

    private var accentFill: LinearGradient {
        switch style {
        case .standard:
            return LinearGradient(colors: [ControllerTheme.accent.opacity(0.7), ControllerTheme.accentWarm.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
        case .hero:
            return LinearGradient(colors: [ControllerTheme.accent, ControllerTheme.accentWarm], startPoint: .leading, endPoint: .trailing)
        case .muted:
            return LinearGradient(colors: [ControllerTheme.accent.opacity(0.35), ControllerTheme.borderStrong.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let tone: Tone

    enum Tone {
        case good
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .good: return ControllerTheme.success
            case .warning: return ControllerTheme.warning
            case .danger: return ControllerTheme.danger
            case .neutral: return ControllerTheme.accent
            }
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(tone.color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(tone.color)
    }
}

struct KVRow: View {
    let key: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ControllerTheme.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .system(size: 13, weight: .medium))
                .foregroundStyle(ControllerTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    let detail: String?
    var tone: StatusBadge.Tone = .neutral

    init(label: String, value: String, detail: String? = nil, tone: StatusBadge.Tone = .neutral) {
        self.label = label
        self.value = value
        self.detail = detail
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ControllerTheme.muted)
                Spacer()
                Circle()
                    .fill(tone.color)
                    .frame(width: 8, height: 8)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ControllerTheme.ink)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ControllerTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tone.color.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var tileFill: Color {
        switch tone {
        case .neutral:
            return ControllerTheme.panelRaised.opacity(0.94)
        case .good:
            return ControllerTheme.success.opacity(0.10)
        case .warning:
            return ControllerTheme.warning.opacity(0.11)
        case .danger:
            return ControllerTheme.danger.opacity(0.10)
        }
    }
}

struct ControllerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ControllerTheme.accent, ControllerTheme.accentWarm],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .shadow(color: ControllerTheme.accent.opacity(configuration.isPressed ? 0.10 : 0.22), radius: 12, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ControllerSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(ControllerTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ControllerTheme.panelRaised.opacity(configuration.isPressed ? 0.78 : 0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ControllerTheme.borderStrong.opacity(0.7), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ControllerTheme.accent.opacity(0.18), ControllerTheme.accentWarm.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 74, height: 74)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(ControllerTheme.accent)
                }
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(ControllerTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(ControllerTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct ScreenshotPreview: View {
    let screenshot: ScreenshotFrame?

    private static let imageCache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image = screenshotImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ControllerTheme.borderStrong, lineWidth: 1)
                    )
            } else {
                EmptyStateView(
                    systemImage: "display",
                    title: "No Snapshot",
                    message: "Refresh the monitor to capture a live screenshot of the selected app."
                )
            }
        }
    }

    private var screenshotImage: NSImage? {
        guard let screenshot
        else {
            return nil
        }

        let cacheKey = NSString(string: "\(screenshot.width)x\(screenshot.height)-\(screenshot.base64PNG.prefix(64))")
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return cached
        }

        guard let data = Data(base64Encoded: screenshot.base64PNG),
              let image = NSImage(data: data)
        else {
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey)
        return image
    }
}
