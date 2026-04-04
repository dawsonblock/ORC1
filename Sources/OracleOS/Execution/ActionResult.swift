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
    public static let recipe            = "recipe"
    public static let stepsCompleted    = "steps_completed"
    public static let totalSteps        = "total_steps"
    public static let durationMs        = "duration_ms"
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

public struct TraceResult: Sendable, Codable, Equatable {
    public let cycleID: String
    public let intentID: String

    public init(cycleID: String, intentID: String) {
        self.cycleID = cycleID
        self.intentID = intentID
    }

    public func toDict() -> [String: Any] {
        [
            TraceResultKey.cycleID: cycleID,
            TraceResultKey.intentID: intentID,
        ]
    }

    public static func from(dict: [String: Any]) -> TraceResult? {
        guard let cycleID = dict[TraceResultKey.cycleID] as? String,
              let intentID = dict[TraceResultKey.intentID] as? String
        else {
            return nil
        }

        return TraceResult(cycleID: cycleID, intentID: intentID)
    }
}

public struct CodeExecutionResult: Sendable, Codable, Equatable {
    public let commandCategory: String?
    public let commandSummary: String?
    public let workspaceRelativePath: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?

    public init(
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        workspaceRelativePath: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil
    ) {
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.workspaceRelativePath = workspaceRelativePath
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [:]
        if let commandCategory {
            result[CodeExecutionResultKey.commandCategory] = commandCategory
        }
        if let commandSummary {
            result[CodeExecutionResultKey.commandSummary] = commandSummary
        }
        if let workspaceRelativePath {
            result[CodeExecutionResultKey.workspaceRelativePath] = workspaceRelativePath
        }
        if let buildResultSummary {
            result[CodeExecutionResultKey.buildResultSummary] = buildResultSummary
        }
        if let testResultSummary {
            result[CodeExecutionResultKey.testResultSummary] = testResultSummary
        }
        if let patchID {
            result[CodeExecutionResultKey.patchID] = patchID
        }
        return result
    }

    public static func from(dict: [String: Any]) -> CodeExecutionResult? {
        let result = CodeExecutionResult(
            commandCategory: dict[CodeExecutionResultKey.commandCategory] as? String,
            commandSummary: dict[CodeExecutionResultKey.commandSummary] as? String,
            workspaceRelativePath: dict[CodeExecutionResultKey.workspaceRelativePath] as? String,
            buildResultSummary: dict[CodeExecutionResultKey.buildResultSummary] as? String,
            testResultSummary: dict[CodeExecutionResultKey.testResultSummary] as? String,
            patchID: dict[CodeExecutionResultKey.patchID] as? String
        )

        return result.isEmpty ? nil : result
    }

    private var isEmpty: Bool {
        commandCategory == nil
            && commandSummary == nil
            && workspaceRelativePath == nil
            && buildResultSummary == nil
            && testResultSummary == nil
            && patchID == nil
    }
}

public struct RecipeStepExecutionResult: Sendable, Codable, Equatable {
    public let stepIndex: Int
    public let action: String
    public let success: Bool
    public let durationMs: Int
    public let error: String?
    public let note: String?

    public init(
        stepIndex: Int,
        action: String,
        success: Bool,
        durationMs: Int,
        error: String? = nil,
        note: String? = nil
    ) {
        self.stepIndex = stepIndex
        self.action = action
        self.success = success
        self.durationMs = durationMs
        self.error = error
        self.note = note
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            RecipeResultKey.stepIndex: stepIndex,
            RecipeResultKey.stepAction: action,
            RecipeResultKey.stepSuccess: success,
            RecipeResultKey.stepDurationMs: durationMs,
        ]
        if let error {
            result[RecipeResultKey.stepError] = error
        }
        if let note {
            result[RecipeResultKey.stepNote] = note
        }
        return result
    }

    public static func from(dict: [String: Any]) -> RecipeStepExecutionResult? {
        guard let action = dict[RecipeResultKey.stepAction] as? String else {
            return nil
        }

        return RecipeStepExecutionResult(
            stepIndex: decodeInt(dict[RecipeResultKey.stepIndex]) ?? 0,
            action: action,
            success: dict[RecipeResultKey.stepSuccess] as? Bool ?? false,
            durationMs: decodeInt(dict[RecipeResultKey.stepDurationMs]) ?? 0,
            error: dict[RecipeResultKey.stepError] as? String,
            note: dict[RecipeResultKey.stepNote] as? String
        )
    }
}

public struct RecipeRunResultPayload: Sendable, Codable, Equatable {
    public let recipeName: String?
    public let stepsCompleted: Int
    public let totalSteps: Int
    public let durationMs: Int?
    public let stepResults: [RecipeStepExecutionResult]
    public let pendingApproval: Bool
    public let approvalRequestID: String?
    public let resumeToken: String?

    public init(
        recipeName: String? = nil,
        stepsCompleted: Int,
        totalSteps: Int,
        durationMs: Int? = nil,
        stepResults: [RecipeStepExecutionResult],
        pendingApproval: Bool = false,
        approvalRequestID: String? = nil,
        resumeToken: String? = nil
    ) {
        self.recipeName = recipeName
        self.stepsCompleted = stepsCompleted
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.stepResults = stepResults
        self.pendingApproval = pendingApproval
        self.approvalRequestID = approvalRequestID
        self.resumeToken = resumeToken
    }

    public func toDict() -> [String: Any] {
        var result: [String: Any] = [
            RecipeResultKey.stepsCompleted: stepsCompleted,
            RecipeResultKey.totalSteps: totalSteps,
            RecipeResultKey.stepResults: stepResults.map { $0.toDict() },
        ]
        if let recipeName {
            result[RecipeResultKey.recipe] = recipeName
        }
        if let durationMs {
            result[RecipeResultKey.durationMs] = durationMs
        }
        if pendingApproval {
            result[RecipeResultKey.pendingApproval] = true
        }
        if let approvalRequestID {
            result[RecipeResultKey.approvalRequestID] = approvalRequestID
        }
        if let resumeToken {
            result[RecipeResultKey.resumeToken] = resumeToken
        }
        return result
    }

    public static func from(data: [String: Any]) -> RecipeRunResultPayload? {
        let hasRecipeShape = data[RecipeResultKey.recipe] != nil
            || data[RecipeResultKey.stepsCompleted] != nil
            || data[RecipeResultKey.totalSteps] != nil
            || data[RecipeResultKey.stepResults] != nil
            || data[RecipeResultKey.pendingApproval] != nil
            || data[RecipeResultKey.resumeToken] != nil
        guard hasRecipeShape else {
            return nil
        }

        let stepResults = (data[RecipeResultKey.stepResults] as? [[String: Any]] ?? []).compactMap {
            RecipeStepExecutionResult.from(dict: $0)
        }

        return RecipeRunResultPayload(
            recipeName: data[RecipeResultKey.recipe] as? String,
            stepsCompleted: decodeInt(data[RecipeResultKey.stepsCompleted]) ?? 0,
            totalSteps: decodeInt(data[RecipeResultKey.totalSteps]) ?? 0,
            durationMs: decodeInt(data[RecipeResultKey.durationMs]),
            stepResults: stepResults,
            pendingApproval: data[RecipeResultKey.pendingApproval] as? Bool ?? false,
            approvalRequestID: data[RecipeResultKey.approvalRequestID] as? String ?? data[ActionResultKey.approvalRequestID] as? String,
            resumeToken: data[RecipeResultKey.resumeToken] as? String
        )
    }
}

private func decodeInt(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    return nil
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
            elapsedMs: (dict[ActionResultKey.elapsedMs] as? Double) ?? Double(dict[ActionResultKey.elapsedMs] as? Int ?? 0),
            policyDecision: (dict[ActionResultKey.policyDecision] as? [String: Any]).flatMap(PolicyDecision.from(dict:)),
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
