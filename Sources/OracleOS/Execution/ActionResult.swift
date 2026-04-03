/// Typed string constants for the dictionary representation of `ActionResult`.
///
/// Using these constants in `toDict()`, `from(dict:)`, and all consuming code
/// eliminates silent key-mismatch bugs caused by inline string literals.
public enum ActionResultKey {
    // ActionResult fields
    public static let success = "success"
    public static let verified = "verified"
    public static let elapsedMs = "elapsed_ms"
    public static let message = "message"
    public static let method = "method"
    public static let verificationStatus = "verification_status"
    public static let failureClass = "failure_class"
    public static let policyDecision = "policy_decision"
    public static let protectedOperation = "protected_operation"
    public static let approvalRequestID = "approval_request_id"
    public static let approvalStatus = "approval_status"
    public static let surface = "surface"
    public static let appProtectionProfile = "app_protection_profile"
    public static let blockedByPolicy = "blocked_by_policy"
    public static let executedThroughExecutor = "executed_through_executor"
    // Top-level ToolResult data keys that nest an ActionResult
    public static let actionResult = "action_result"
    public static let trace = "trace"
    public static let codeExecution = "code_execution"
}

/// Typed constants for keys in the trace sub-object produced by RuntimeExecutionDriver.
public enum TraceResultKey {
    public static let cycleID  = "cycle_id"
    public static let intentID = "intent_id"
}

/// Typed constants for recipe-run result dictionary keys.
/// Producer: RecipeEngine. Consumer: ControllerRuntimeBridge+Mapping.mapRecipeRunResult.
public enum RecipeResultKey {
    public static let stepsCompleted    = "steps_completed"
    public static let totalSteps        = "total_steps"
    public static let stepResults       = "step_results"
    public static let pendingApproval   = "pending_approval"
    public static let approvalRequestID = "approval_request_id"
    public static let resumeToken       = "resume_token"
    // Step sub-object keys
    public static let stepIndex         = "step"
    public static let stepAction        = "action"
    public static let stepSuccess       = "success"
    public static let stepDurationMs    = "duration_ms"
    public static let stepError         = "error"
    public static let stepNote          = "note"
}

/// Typed constants for keys in the `code_execution` sub-dict.
/// Producer: CodeRouter / ExecutionSemanticsEncoder / ActionContract.
/// Consumer: ControllerRuntimeBridge+Mapping.mapActionResult (codeData probe).
public enum CodeExecutionResultKey {
    public static let commandCategory       = "command_category"
    /// Human-readable summary of the command. The dict key is "summary".
    public static let commandSummary        = "summary"
    public static let workspaceRelativePath = "workspace_relative_path"
    public static let buildResultSummary    = "build_result_summary"
    public static let testResultSummary     = "test_result_summary"
    public static let patchID               = "patch_id"
}

public struct ActionResult: Sendable, Codable {
    public let success: Bool
    public let verified: Bool
    public let message: String?
    public let method: String?
    public let verificationStatus: VerificationStatus?
    public let failureClass: String?
    public let elapsedMs: Double
    public let policyDecision: PolicyDecision?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalStatus: String?
    public let surface: String?
    public let appProtectionProfile: String?
    public let blockedByPolicy: Bool

    /// True when the action was executed through ``VerifiedExecutor``.
    /// Every action in the runtime loop must pass through the executor;
    /// consuming code can assert this flag to enforce the trust boundary.
    public let executedThroughExecutor: Bool

    public init(
        success: Bool,
        verified: Bool? = nil,
        message: String? = nil,
        method: String? = nil,
        verificationStatus: VerificationStatus? = nil,
        failureClass: String? = nil,
        elapsedMs: Double = 0,
        policyDecision: PolicyDecision? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalStatus: String? = nil,
        surface: String? = nil,
        appProtectionProfile: String? = nil,
        blockedByPolicy: Bool = false,
        executedThroughExecutor: Bool = false
    ) {
        self.success = success
        self.verified = verified ?? success
        self.message = message
        self.method = method
        self.verificationStatus = verificationStatus
        self.failureClass = failureClass
        self.elapsedMs = elapsedMs
        self.policyDecision = policyDecision
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalStatus = approvalStatus
        self.surface = surface
        self.appProtectionProfile = appProtectionProfile
        self.blockedByPolicy = blockedByPolicy
        self.executedThroughExecutor = executedThroughExecutor
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            ActionResultKey.success: success,
            ActionResultKey.verified: verified,
            ActionResultKey.elapsedMs: elapsedMs,
        ]

        if let message {
            result[ActionResultKey.message] = message
        }
        if let method {
            result[ActionResultKey.method] = method
        }
        if let verificationStatus {
            result[ActionResultKey.verificationStatus] = verificationStatus.rawValue
        }
        if let failureClass {
            result[ActionResultKey.failureClass] = failureClass
        }
        if let policyDecision {
            result[ActionResultKey.policyDecision] = policyDecision.toDict()
        }
        if let protectedOperation {
            result[ActionResultKey.protectedOperation] = protectedOperation
        }
        if let approvalRequestID {
            result[ActionResultKey.approvalRequestID] = approvalRequestID
        }
        if let approvalStatus {
            result[ActionResultKey.approvalStatus] = approvalStatus
        }
        if let surface {
            result[ActionResultKey.surface] = surface
        }
        if let appProtectionProfile {
            result[ActionResultKey.appProtectionProfile] = appProtectionProfile
        }
        result[ActionResultKey.blockedByPolicy] = blockedByPolicy
        result[ActionResultKey.executedThroughExecutor] = executedThroughExecutor

        return result
    }

    public static func from(dict: [String: Any]) -> ActionResult? {
        guard let success = dict[ActionResultKey.success] as? Bool else {
            return nil
        }

        let verificationStatus: VerificationStatus?
        if let raw = dict[ActionResultKey.verificationStatus] as? String {
            verificationStatus = VerificationStatus(rawValue: raw)
        } else {
            verificationStatus = nil
        }

        return ActionResult(
            success: success,
            verified: dict[ActionResultKey.verified] as? Bool ?? success,
            message: dict[ActionResultKey.message] as? String,
            method: dict[ActionResultKey.method] as? String,
            verificationStatus: verificationStatus,
            failureClass: dict[ActionResultKey.failureClass] as? String,
            elapsedMs: dict[ActionResultKey.elapsedMs] as? Double ?? 0,
            policyDecision: nil,
            protectedOperation: dict[ActionResultKey.protectedOperation] as? String,
            approvalRequestID: dict[ActionResultKey.approvalRequestID] as? String,
            approvalStatus: dict[ActionResultKey.approvalStatus] as? String,
            surface: dict[ActionResultKey.surface] as? String,
            appProtectionProfile: dict[ActionResultKey.appProtectionProfile] as? String,
            blockedByPolicy: dict[ActionResultKey.blockedByPolicy] as? Bool ?? false,
            executedThroughExecutor: dict[ActionResultKey.executedThroughExecutor] as? Bool ?? false
        )
    }
}
