import Foundation

/// Translates legacy ActionIntent into the canonical Intent model and submits via IntentAPI.
///
/// SCOPE: This is a typed translation bridge, not an alternate execution path.
/// It converts ActionIntent (external UI automation input) → Intent → RuntimeOrchestrator.submitIntent().
/// Every execution call passes through RuntimeOrchestrator. There is no direct executor access here.
///
/// INVARIANT: This file must NEVER call VerifiedExecutor, DefaultProcessAdapter,
/// CommandRouter, or any other execution layer directly. If you find such a call, it is a bug.
/// All execution is mediated by IntentAPI (implemented by RuntimeOrchestrator).
@MainActor
public final class RuntimeExecutionDriver: AgentExecutionDriver {
    private final class SubmissionState: @unchecked Sendable {
        var result: ToolResult

        init(result: ToolResult) {
            self.result = result
        }
    }

    private let surface: RuntimeSurface
    private let intentAPI: any IntentAPI
    private static let submissionTimeoutSeconds: TimeInterval = 60

    /// Preferred init — translates ActionIntent to Intent and submits via IntentAPI.
    /// This is a pure translator: it converts external input into Intent and forwards it.
    public init(
        intentAPI: any IntentAPI,
        surface: RuntimeSurface = .recipe
    ) {
        self.intentAPI = intentAPI
        self.surface = surface
    }

    // MARK: - AgentExecutionDriver conformance

    public func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        executeViaIntentAPI(
            intentAPI,
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: selectedCandidate,
            approvalToken: nil
        )
    }

    /// Extended form that threads an approval token from a prior approval-pending cycle.
    func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?,
        approvalToken: String?
    ) -> ToolResult {
        executeViaIntentAPI(
            intentAPI,
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: selectedCandidate,
            approvalToken: approvalToken
        )
    }

    // MARK: - IntentAPI translation path

    /// Translates ActionIntent to the typed Intent model and submits via IntentAPI.
    /// This is the approved path — no direct executor calls.
    private func executeViaIntentAPI(
        _ api: any IntentAPI,
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?,
        approvalToken: String? = nil
    ) -> ToolResult {
        let codeExecutionResult = Self.makeCodeExecutionResult(from: intent)
        let domain: IntentDomain = intent.agentKind == .code ? .code :
            .ui

        var metadata = [
            "query": intent.query ?? intent.text ?? intent.name,
            "source": "runtime-execution-driver.\(surface.rawValue)",
            "surface": surface.rawValue,
            "plannerSource": plannerDecision.source.rawValue,
            "plannerFamily": plannerDecision.plannerFamily.rawValue,
        ]
        if let selectedCandidate {
            metadata["selectedElementID"] = selectedCandidate.element.id
            metadata["selectedElementLabel"] = selectedCandidate.element.label
        }
        if let encodedIntent = Self.encodeActionIntent(intent) {
            metadata["action_intent_base64"] = encodedIntent
        }
        // Thread approval token so the orchestrator can attach it to the command
        // for VerifiedExecutor to validate and consume.
        if let approvalToken {
            metadata["approvalToken"] = approvalToken
        }

        let typedIntent = Intent(
            domain: domain,
            objective: intent.name,
            metadata: metadata
        )

        // Submit intent via API — the sole approved execution gateway
        let submissionState = SubmissionState(
            result: ToolResult(success: false, error: "IntentAPI submission pending")
        )
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) { [submissionState, semaphore] in
            do {
                let response = try await api.submitIntent(typedIntent)
                submissionState.result = Self.makeToolResult(
                    from: response,
                    codeExecutionResult: codeExecutionResult
                )
            } catch {
                submissionState.result = ToolResult(
                    success: false,
                    data: ["summary": "Intent submission failed"],
                    error: error.localizedDescription,
                    actionResult: ActionResult(
                        success: false,
                        verified: false,
                        message: error.localizedDescription,
                        method: "intent-api",
                        failureClass: "intent_submission_failed",
                        executedThroughExecutor: false
                    ),
                    codeExecutionResult: codeExecutionResult
                )
            }
            semaphore.signal()
        }

        let timedOut: Bool = {
            if Thread.isMainThread {
                // Keep the main run loop pumping while we synchronously wait so
                // MainActor-bound executor work can complete without deadlocking.
                let deadline = Date().addingTimeInterval(Self.submissionTimeoutSeconds)
                while Date() < deadline {
                    if semaphore.wait(timeout: .now()) == .success {
                        return false
                    }
                    _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
                }
                return true
            }
            return semaphore.wait(timeout: .now() + Self.submissionTimeoutSeconds) == .timedOut
        }()

        if timedOut {
            return ToolResult(
                success: false,
                data: ["summary": "Intent submission timed out"],
                error: "Intent submission timed out after \(Int(Self.submissionTimeoutSeconds))s",
                actionResult: ActionResult(
                    success: false,
                    verified: false,
                    message: "Intent submission timed out after \(Int(Self.submissionTimeoutSeconds))s",
                    method: "intent-api",
                    failureClass: "intent_submission_timeout",
                    executedThroughExecutor: false
                ),
                codeExecutionResult: codeExecutionResult
            )
        }

        return submissionState.result
    }

    nonisolated private static func makeToolResult(
        from response: IntentResponse,
        codeExecutionResult: CodeExecutionResult?
    ) -> ToolResult {
        let success = response.outcome == .success
            || response.outcome == .skipped
            || response.outcome == .partialSuccess
        let isPlanningFailure = response.summary.lowercased().hasPrefix("planning failed")
        let isApprovalPending = response.approvalRequestID != nil
        let verified = response.outcome == .success || response.outcome == .skipped

        let failureClass: String?
        if response.outcome == .partialSuccess {
            failureClass = "partial_success"
        } else if response.outcome == .failed {
            if isApprovalPending {
                failureClass = "approval_pending"
            } else {
                failureClass = isPlanningFailure ? "planning_failed" : "runtime_failed"
            }
        } else {
            failureClass = nil
        }

        let actionResult = ActionResult(
            success: success,
            verified: verified,
            message: response.summary,
            method: "intent-api",
            failureClass: failureClass,
            approvalRequestID: response.approvalRequestID,
            approvalStatus: response.approvalStatus,
            executedThroughExecutor: !isPlanningFailure && !isApprovalPending
        )

        let traceResult = TraceResult(
            cycleID: response.cycleID.uuidString,
            intentID: response.intentID.uuidString
        )

        var data: [String: Any] = [
            "summary": response.summary,
            "cycleID": response.cycleID.uuidString,
        ]
        if let snapshotID = response.snapshotID {
            data["snapshot_id"] = snapshotID.uuidString
        }

        return ToolResult(
            success: success,
            data: data,
            error: response.outcome == .failed ? response.summary : nil,
            actionResult: actionResult,
            traceResult: traceResult,
            codeExecutionResult: codeExecutionResult
        )
    }

    nonisolated private static func makeCodeExecutionResult(from intent: ActionIntent) -> CodeExecutionResult? {
        guard intent.agentKind == .code else {
            return nil
        }

        let codeExecutionResult = CodeExecutionResult(
            commandCategory: intent.commandCategory,
            commandSummary: intent.commandSummary,
            workspaceRelativePath: intent.workspaceRelativePath
        )

        return codeExecutionResult.toDict().isEmpty ? nil : codeExecutionResult
    }

    private static func encodeActionIntent(_ intent: ActionIntent) -> String? {
        guard let data = try? JSONEncoder().encode(intent) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
