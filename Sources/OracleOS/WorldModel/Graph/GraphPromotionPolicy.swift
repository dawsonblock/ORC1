import Foundation

public struct GraphPromotionPolicy: Sendable {
    public let minAttempts: Int
    public let minSuccessRate: Double
    public let minPostconditionConsistency: Double
    public let maxTargetAmbiguityRate: Double
    public let successRecencyDays: Int
    public let demotionRollingSuccessRate: Double
    public let pruneAttempts: Int
    public let pruneSuccessRate: Double
    public let pruneDays: Int
    public let freezeGlobalSuccessRate: Double

    public init(
        minAttempts: Int = 5,
        minSuccessRate: Double = 0.8,
        minPostconditionConsistency: Double = 0.9,
        maxTargetAmbiguityRate: Double = 0.2,
        successRecencyDays: Int = 7,
        demotionRollingSuccessRate: Double = 0.5,
        pruneAttempts: Int = 10,
        pruneSuccessRate: Double = 0.3,
        pruneDays: Int = 14,
        freezeGlobalSuccessRate: Double = 0.5
    ) {
        self.minAttempts = minAttempts
        self.minSuccessRate = minSuccessRate
        self.minPostconditionConsistency = minPostconditionConsistency
        self.maxTargetAmbiguityRate = maxTargetAmbiguityRate
        self.successRecencyDays = successRecencyDays
        self.demotionRollingSuccessRate = demotionRollingSuccessRate
        self.pruneAttempts = pruneAttempts
        self.pruneSuccessRate = pruneSuccessRate
        self.pruneDays = pruneDays
        self.freezeGlobalSuccessRate = freezeGlobalSuccessRate
    }

    public func promotionsFrozen(globalVerifiedSuccessRate: Double) -> Bool {
        globalVerifiedSuccessRate < freezeGlobalSuccessRate
    }

    public func shouldPromote(edge: EdgeTransition, now: Date) -> Bool {
        guard edge.recoveryTagged == false else { return false }
        guard edge.knowledgeTier != .experiment else { return false }
        guard edge.knowledgeTier != .recovery else { return false }
        guard edge.attempts >= minAttempts else { return false }
        guard edge.successRate >= minSuccessRate else { return false }
        guard edge.postconditionConsistency >= minPostconditionConsistency else { return false }
        guard edge.targetAmbiguityRate <= maxTargetAmbiguityRate else { return false }
        guard let lastSuccessTimestamp = edge.lastSuccessTimestamp else { return false }
        let age = now.timeIntervalSince1970 - lastSuccessTimestamp
        return age <= TimeInterval(successRecencyDays * 86_400)
    }

    public func shouldDemote(edge: EdgeTransition) -> Bool {
        edge.rollingSuccessRate < demotionRollingSuccessRate
    }

    public func shouldPrune(edge: EdgeTransition, now: Date) -> Bool {
        guard edge.attempts >= pruneAttempts else { return false }
        guard edge.successRate <= pruneSuccessRate else { return false }
        guard let lastSuccessTimestamp = edge.lastSuccessTimestamp else { return true }
        let age = now.timeIntervalSince1970 - lastSuccessTimestamp
        return age >= TimeInterval(pruneDays * 86_400)
    }
}
