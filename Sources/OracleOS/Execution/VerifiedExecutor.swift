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

    public init(
        policyEngine: PolicyEngine,
        commandRouter: CommandRouter,
        preconditionsValidator: PreconditionsValidator,
        postconditionsValidator: PostconditionsValidator,
        stateProvider: (any WorldStateProviding)? = nil
    ) {
        self.policyEngine = policyEngine
        self.commandRouter = commandRouter
        self.preconditionsValidator = preconditionsValidator
        self.postconditionsValidator = postconditionsValidator
        self.stateProvider = stateProvider
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
