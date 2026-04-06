import Foundation

public enum RuntimeControlPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case fullControl = "full-control"
    case original
    case less
    case aiDecides = "ai-decides"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullControl:
            return "Full Control"
        case .original:
            return "Original"
        case .less:
            return "Less"
        case .aiDecides:
            return "AI Decides"
        }
    }

    public var summary: String {
        switch self {
        case .fullControl:
            return "Approvals stay out of the way unless the runtime hits a hard safety block."
        case .original:
            return "Current default behavior: risky actions pause for review."
        case .less:
            return "Stricter review posture: risky actions are blocked instead of queued."
        case .aiDecides:
            return "Adaptive posture: block irreversible or external risk, review the rest."
        }
    }

    public var shortSummary: String {
        switch self {
        case .fullControl:
            return "Fewer approvals"
        case .original:
            return "Current default"
        case .less:
            return "Stricter"
        case .aiDecides:
            return "Adaptive"
        }
    }
}