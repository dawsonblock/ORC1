import Foundation

public struct PolicyDecision: Codable, Sendable {
    public let allowed: Bool
    public let riskLevel: RiskLevel
    public let requiresApproval: Bool
    public let protectedOperation: ProtectedOperation?
    public let approvalRequestID: String?
    public let appProtectionProfile: AppProtectionProfile
    public let blockedByPolicy: Bool
    public let surface: RuntimeSurface
    public let policyMode: PolicyMode
    public let reason: String?

    public init(
        allowed: Bool,
        riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation? = nil,
        approvalRequestID: String? = nil,
        appProtectionProfile: AppProtectionProfile = .lowRiskAllowed,
        blockedByPolicy: Bool = false,
        surface: RuntimeSurface = .mcp,
        policyMode: PolicyMode = .confirmRisky,
        requiresApproval: Bool = false,
        reason: String? = nil
    ) {
        self.allowed = allowed
        self.riskLevel = riskLevel
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.surface = surface
        self.policyMode = policyMode
        self.requiresApproval = requiresApproval
        self.reason = reason
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            "allowed": allowed,
            "risk_level": riskLevel.rawValue,
            "requires_approval": requiresApproval,
            "app_protection_profile": appProtectionProfile.rawValue,
            "blocked_by_policy": blockedByPolicy,
            "surface": surface.rawValue,
            "policy_mode": policyMode.rawValue,
        ]
        if let protectedOperation {
            result["protected_operation"] = protectedOperation.rawValue
        }
        if let approvalRequestID {
            result["approval_request_id"] = approvalRequestID
        }
        if let reason {
            result["reason"] = reason
        }
        return result
    }

    public func withApprovalRequest(id: String) -> PolicyDecision {
        PolicyDecision(
            allowed: false,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            approvalRequestID: id,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: blockedByPolicy,
            surface: surface,
            policyMode: policyMode,
            requiresApproval: true,
            reason: reason
        )
    }

    public func withReason(_ reason: String) -> PolicyDecision {
        PolicyDecision(
            allowed: false,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            approvalRequestID: approvalRequestID,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: true,
            surface: surface,
            policyMode: policyMode,
            requiresApproval: requiresApproval,
            reason: reason
        )
    }

    public static func from(dict: [String: Any]) -> PolicyDecision? {
        guard let allowed = dict["allowed"] as? Bool,
              let riskRaw = dict["risk_level"] as? String,
              let riskLevel = RiskLevel(rawValue: riskRaw),
              let appProfileRaw = dict["app_protection_profile"] as? String,
              let appProtectionProfile = AppProtectionProfile(rawValue: appProfileRaw),
              let surfaceRaw = dict["surface"] as? String,
              let surface = RuntimeSurface(rawValue: surfaceRaw),
              let policyModeRaw = dict["policy_mode"] as? String,
              let policyMode = PolicyMode(rawValue: policyModeRaw)
        else {
            return nil
        }

        return PolicyDecision(
            allowed: allowed,
            riskLevel: riskLevel,
            protectedOperation: (dict["protected_operation"] as? String).flatMap(ProtectedOperation.init(rawValue:)),
            approvalRequestID: dict["approval_request_id"] as? String,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: dict["blocked_by_policy"] as? Bool ?? false,
            surface: surface,
            policyMode: policyMode,
            requiresApproval: dict["requires_approval"] as? Bool ?? false,
            reason: dict["reason"] as? String
        )
    }
}
