import Foundation

public final class EdgeTransition: @unchecked Sendable {
    public let edgeID: String
    public let fromPlanningStateID: PlanningStateID
    public var toPlanningStateID: PlanningStateID
    public let actionContractID: String
    public let agentKind: AgentKind
    public let domain: String
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let plannerFamily: String?
    public let postconditionClass: PostconditionClass
    public var attempts: Int
    public var successes: Int
    public var latencyTotalMs: Int
    public var failureHistogram: [String: Int]
    public var lastSuccessTimestamp: TimeInterval?
    public var lastAttemptTimestamp: TimeInterval?
    public var recentOutcomes: [Bool]
    public var ambiguityTotal: Double
    public var recoveryTagged: Bool
    public var approvalRequired: Bool
    public var approvalOutcome: String?
    public var knowledgeTier: KnowledgeTier

    public init(
        edgeID: String,
        fromPlanningStateID: PlanningStateID,
        toPlanningStateID: PlanningStateID,
        actionContractID: String,
        agentKind: AgentKind = .os,
        domain: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        plannerFamily: String? = nil,
        postconditionClass: PostconditionClass,
        attempts: Int = 0,
        successes: Int = 0,
        latencyTotalMs: Int = 0,
        failureHistogram: [String: Int] = [:],
        lastSuccessTimestamp: TimeInterval? = nil,
        lastAttemptTimestamp: TimeInterval? = nil,
        recentOutcomes: [Bool] = [],
        ambiguityTotal: Double = 0,
        recoveryTagged: Bool = false,
        approvalRequired: Bool = false,
        approvalOutcome: String? = nil,
        knowledgeTier: KnowledgeTier = .candidate
    ) {
        self.edgeID = edgeID
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.actionContractID = actionContractID
        self.agentKind = agentKind
        self.domain = domain ?? (agentKind == .code ? "code" : "os")
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.plannerFamily = plannerFamily
        self.postconditionClass = postconditionClass
        self.attempts = attempts
        self.successes = successes
        self.latencyTotalMs = latencyTotalMs
        self.failureHistogram = failureHistogram
        self.lastSuccessTimestamp = lastSuccessTimestamp
        self.lastAttemptTimestamp = lastAttemptTimestamp
        self.recentOutcomes = recentOutcomes
        self.ambiguityTotal = ambiguityTotal
        self.recoveryTagged = recoveryTagged
        self.approvalRequired = approvalRequired
        self.approvalOutcome = approvalOutcome
        self.knowledgeTier = knowledgeTier
    }

    public var successRate: Double {
        guard attempts > 0 else { return 0 }
        return Double(successes) / Double(attempts)
    }

    public var averageLatencyMs: Double {
        guard attempts > 0 else { return 0 }
        return Double(latencyTotalMs) / Double(attempts)
    }

    public var confidence: Double {
        let attemptsFactor = min(Double(attempts) / 10.0, 1.0)
        return successRate * attemptsFactor
    }

    public var postconditionConsistency: Double {
        postconditionClass == .unknown ? 0.5 : 1.0
    }

    public var targetAmbiguityRate: Double {
        guard attempts > 0 else { return 0 }
        return min(max(ambiguityTotal / Double(attempts), 0), 1)
    }

    public var rollingSuccessRate: Double {
        let window = recentOutcomes.suffix(5)
        guard !window.isEmpty else { return successRate }
        return Double(window.filter { $0 }.count) / Double(window.count)
    }

    public var cost: Double {
        let failureRate = 1.0 - successRate
        let normalizedLatency = min(averageLatencyMs / 2_000.0, 1.0)
        let uncertainty = 1.0 - confidence
        let noveltyBonus = attempts < 3 ? -0.05 : 0
        return failureRate + (0.35 * normalizedLatency) + (0.5 * uncertainty) + noveltyBonus
    }

    public func record(_ transition: VerifiedTransition) {
        attempts += 1
        lastAttemptTimestamp = transition.timestamp
        if let targetAmbiguityScore = transition.targetAmbiguityScore {
            ambiguityTotal += min(max(targetAmbiguityScore, 0), 1)
        }
        recoveryTagged = recoveryTagged || transition.recoveryTagged
        approvalRequired = approvalRequired || transition.approvalRequired
        if knowledgeTier != .stable {
            knowledgeTier = transition.knowledgeTier
        }
        if let approvalOutcome = transition.approvalOutcome {
            self.approvalOutcome = approvalOutcome
        }
        recentOutcomes.append(transition.verified)
        if recentOutcomes.count > 5 {
            recentOutcomes.removeFirst(recentOutcomes.count - 5)
        }
        if transition.verified {
            successes += 1
            toPlanningStateID = transition.toPlanningStateID
            lastSuccessTimestamp = transition.timestamp
        } else if let failureClass = transition.failureClass {
            failureHistogram[failureClass, default: 0] += 1
        }
        latencyTotalMs += transition.latencyMs
    }
}
