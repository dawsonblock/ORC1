import Foundation

/// Verified execution layer — the policy-checked gateway for **Tier-2 reversible**
/// and **Tier-3 destructive** side effects in Oracle-OS.
///
/// Side-effect taxonomy (three tiers):
///   Tier 1 — Read-only: AXScanner, VisionScanner, memory queries.
///             No VerifiedExecutor involvement required.
///   Tier 2 — Reversible: UI automation (click, type, hotkey, scroll, focus, window).
///             MUST route through VerifiedExecutor.execute().
///   Tier 3 — Destructive / persistent: file writes, shell escapes, recipe saves,
///             architecture mutations. MUST route through VerifiedExecutor.execute().
///
/// Note: Persistence writes (Tier 3) originate from Persistence-namespaced stores.
/// The vision sidecar (Tier 1) is called directly from VisionScanner — no executor
/// involvement because it is read-only.
///
/// INVARIANTS:
///   - Executor observes and acts, but does NOT commit state
///   - Executor returns ExecutionOutcome with events and artifacts only
///   - CommitCoordinator is the ONLY entity that writes committed state
///   - Tier-2 and Tier-3 effects MUST route through this actor's execute() method
///
/// ENFORCEMENT:
///   - All CLI tools, planners, routers MUST use RuntimeOrchestrator.submitIntent()
///   - Bypassing this path for Tier-2/3 effects is an architectural violation
///   - Governance tests verify Tier-2/3 effects route through here
public actor VerifiedExecutor {
    private let policyEngine: PolicyEngine
    private let commandRouter: CommandRouter
    private let preconditionsValidator: PreconditionsValidator
    private let postconditionsValidator: PostconditionsValidator
    private let stateProvider: (any WorldStateProviding)?
    private let approvalStore: ApprovalStore?

    public init(
        policyEngine: PolicyEngine,
        commandRouter: CommandRouter,
        preconditionsValidator: PreconditionsValidator,
        postconditionsValidator: PostconditionsValidator,
        stateProvider: (any WorldStateProviding)? = nil,
        approvalStore: ApprovalStore? = nil
    ) {
        self.policyEngine = policyEngine
        self.commandRouter = commandRouter
        self.preconditionsValidator = preconditionsValidator
        self.postconditionsValidator = postconditionsValidator
        self.stateProvider = stateProvider
        self.approvalStore = approvalStore
    }

    /// Execute a validated command and return outcome with events.
    ///
    /// This is the ONLY public method allowed to execute commands.
    /// IMPORTANT: This does NOT commit state — only returns events for CommitCoordinator.
    ///
    /// ENFORCEMENT: All side effects MUST route through this method:
    ///   - Process execution → WorkspaceRunner → DefaultProcessAdapter
    ///   - File mutations → FileMutationSpec → WorkspaceRunner.applyFile()
    ///   - UI interactions → UIRouter → AutomationHost
    ///
    /// Bypassing this method is an architectural violation and will be caught by:
    ///   - Governance tests (ExecutionBoundaryTests)
    ///   - Type system (no alternate execute() paths)
    ///   - Static analysis (grep for shell escapes, .write(to:), FileManager outside this actor)
    public func execute(_ command: Command) async throws -> ExecutionOutcome {
        // GUARD: Verify command is typed (no shell escape hatch)
        switch command.payload {
        case .build, .test, .git, .file, .ui, .code:
            // Typed command OK — proceed
            break
        }

        // Check preconditions against current world state
        if let provider = stateProvider {
            let snapshot = await provider.snapshot()
            do {
                _ = try preconditionsValidator.validate(command, state: snapshot)
            } catch let error as PreconditionError {
                return failOutcome(
                    command: command,
                    status: .preconditionFailed,
                    reason: error.description
                )
            }
        }

        let policyDecision = try policyEngine.validate(command)

        // GUARD: Approval gate — halt execution and create an approval request when
        // the policy engine marks the action as risky-but-approvable. The caller
        // receives an .approvalPending outcome and must poll / wait for the user to
        // approve via the Controller UI (or CLI) before re-submitting.
        if policyDecision.requiresApproval,
           let store = approvalStore,
           let protectedOp = policyDecision.protectedOperation
        {
            let request = ApprovalRequest(
                surface: policyDecision.surface,
                toolName: command.kind,
                appName: nil,
                displayTitle: "\(command.kind) requires approval",
                reason: policyDecision.reason ?? "Action classified as risky",
                riskLevel: policyDecision.riskLevel,
                protectedOperation: protectedOp,
                actionFingerprint: command.id.uuidString,
                appProtectionProfile: policyDecision.appProtectionProfile
            )
            _ = try store.createRequest(request)
            return approvalPendingOutcome(
                command: command,
                requestID: request.id,
                reason: policyDecision.reason ?? "Approval required"
            )
        }

        guard policyDecision.allowed else {
            return failOutcome(
                command: command,
                status: .policyBlocked,
                reason: policyDecision.reason ?? "Policy rejected"
            )
        }

        do {
            var outcome = try await commandRouter.execute(command, policyDecision: policyDecision)

            guard try postconditionsValidator.validate(command, outcome: outcome) else {
                return failOutcome(
                    command: command,
                    status: .postconditionFailed,
                    reason: "Postconditions failed"
                )
            }

            // GUARD: Ensure events are present (every execution must produce audit trail)
            if outcome.events.isEmpty {
                let event = DomainEventFactory.commandExecuted(
                    command: command,
                    status: "success"
                )
                outcome = ExecutionOutcome(
                    commandID: outcome.commandID,
                    status: outcome.status,
                    observations: outcome.observations,
                    artifacts: outcome.artifacts,
                    events: [event],
                    verifierReport: outcome.verifierReport
                )
            }
            return outcome
        } catch {
            return failOutcome(
                command: command,
                status: .failed,
                reason: error.localizedDescription
            )
        }
    }

    private func approvalPendingOutcome(command: Command, requestID: String, reason: String) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: true,
            policyDecision: "approval-pending:\(requestID)",
            postconditionsPassed: false,
            notes: [reason]
        )
        let event = DomainEventFactory.commandFailed(command: command, error: "approval-pending:\(requestID)")
        return ExecutionOutcome(
            commandID: command.id,
            status: .approvalPending,
            observations: [],
            artifacts: [],
            events: [event],
            verifierReport: report
        )
    }

    private func failOutcome(
        command: Command,
        status: ExecutionStatus,
        reason: String
    ) -> ExecutionOutcome {
        let report = VerifierReport(
            commandID: command.id,
            preconditionsPassed: status != .preconditionFailed,
            policyDecision: status == .policyBlocked ? reason : "approved",
            postconditionsPassed: status != .postconditionFailed,
            notes: [reason]
        )
        let event = DomainEventFactory.commandFailed(command: command, error: reason)
        return ExecutionOutcome(
            commandID: command.id,
            status: status,
            observations: [],
            artifacts: [],
            events: [event],
            verifierReport: report
        )
    }
}
