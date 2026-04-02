import Foundation

public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case os
    case code
}

public enum PlannerFamily: String, Codable, Sendable, CaseIterable {
    case os
    case code
}

public enum TaskStepPhase: String, Codable, Sendable, CaseIterable {
    case operatingSystem
    case engineering
    case handoff
}
