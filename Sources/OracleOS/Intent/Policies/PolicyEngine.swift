import Foundation

public final class PolicyEngine: @unchecked Sendable {
    public static let shared = PolicyEngine()

    private var currentMode: PolicyMode

    /// Cache for policy decisions to avoid repeated evaluation
    private var decisionCache: [String: CachedDecision] = [:]
    private let cacheLock = NSLock()

    /// Cache TTL in seconds (default 5 minutes)
    private let cacheTTL: TimeInterval = 300

    /// Repeated-action guard: tracks consecutive occurrences of the same
    /// protected operation. After `maxConsecutiveProtectedOps` hits the action
    /// is blocked, preventing tight loops that hammer risky operations.
    private var lastProtectedOperation: ProtectedOperation? = nil
    private var consecutiveProtectedOpCount: Int = 0
    private let maxConsecutiveProtectedOps: Int = 3

    /// Cached decision with timestamp for TTL tracking
    private struct CachedDecision {
        let decision: PolicyDecision
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300
        }
    }

    public var mode: PolicyMode {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return currentMode
    }

    public init(mode: PolicyMode? = nil) {
        self.currentMode = mode ?? Self.defaultMode()
    }

    /// Reset the repeated-action guard (call when world state changes).
    public func resetRepeatedActionGuard() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        lastProtectedOperation = nil
        consecutiveProtectedOpCount = 0
    }

    /// Clear the policy decision cache (call after hot-reload)
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        decisionCache.removeAll()
        Log.info("PolicyEngine: Decision cache cleared")
    }

    /// Reload policies with immediate cache invalidation
    public func reloadPolicies(mode: PolicyMode? = nil) {
        cacheLock.lock()
        let previousMode = currentMode
        if let mode {
            currentMode = mode
        }
        decisionCache.removeAll()
        lastProtectedOperation = nil
        consecutiveProtectedOpCount = 0
        let activeMode = currentMode
        cacheLock.unlock()

        if previousMode != activeMode || mode == nil {
            Log.info("PolicyEngine: reloaded policies in \(activeMode.rawValue) mode")
        }
    }

    public func evaluate(intent: ActionIntent) -> PolicyDecision {
        evaluate(
            intent: intent,
            context: PolicyEvaluationContext(
                surface: .mcp,
                toolName: nil,
                appName: intent.app,
                agentKind: intent.agentKind,
                workspaceRoot: intent.workspaceRoot,
                workspaceRelativePath: intent.workspaceRelativePath,
                commandCategory: intent.commandCategory
            )
        )
    }

    /// Canonical command-level policy validation used by VerifiedExecutor.
    /// No executable path validation — only typed command validation.
    public func validate(_ command: Command) throws -> PolicyDecision {
        let intent = actionIntent(from: command)
        let context = PolicyEvaluationContext(
            surface: surface(from: command.metadata.source),
            toolName: command.kind,
            appName: intent.app,
            agentKind: intent.agentKind,
            workspaceRoot: intent.workspaceRoot,
            workspaceRelativePath: intent.workspaceRelativePath,
            commandCategory: intent.commandCategory
        )
        return evaluate(intent: intent, context: context)
    }

    private func commandSpec(for action: CodeAction) -> CommandSpec? {
        guard let workspaceRoot = action.workspacePath, !workspaceRoot.isEmpty else {
            return nil
        }

        switch action.name {
        case "readFile", CodeCommandCategory.openFile.rawValue:
            let path = action.filePath
            let summary = path.map { "open \($0)" } ?? "open file"
            return CommandSpec(
                category: .openFile,
                executable: "/usr/bin/env",
                arguments: path.map { [$0] } ?? [],
                workspaceRoot: workspaceRoot,
                workspaceRelativePath: path,
                summary: summary
            )
        case "searchRepository", CodeCommandCategory.searchCode.rawValue:
            let query = action.query ?? ""
            let summary = query.isEmpty ? "search code" : "search code for \(query)"
            return CommandSpec(
                category: .searchCode,
                executable: "/usr/bin/env",
                arguments: query.isEmpty ? [] : [query],
                workspaceRoot: workspaceRoot,
                summary: summary
            )
        case CodeCommandCategory.indexRepository.rawValue:
            return CommandSpec(
                category: .indexRepository,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: workspaceRoot,
                summary: "index repository"
            )
        default:
            return nil
        }
    }

    private func actionIntent(from command: Command) -> ActionIntent {
        switch command.payload {
        case .build(let spec):
            return ActionIntent(
                agentKind: .code,
                app: "Workspace",
                name: "build",
                action: "build",
                workspaceRoot: spec.workspaceRoot,
                postconditions: []
            )
        case .test(let spec):
            return ActionIntent(
                agentKind: .code,
                app: "Workspace",
                name: "test",
                action: "test",
                workspaceRoot: spec.workspaceRoot,
                postconditions: []
            )
        case .git(let spec):
            return ActionIntent(
                agentKind: .code,
                app: "Workspace",
                name: "git-\(spec.operation.rawValue)",
                action: "git",
                workspaceRoot: spec.workspaceRoot,
                postconditions: []
            )
        case .file(let spec):
            return ActionIntent(
                agentKind: .code,
                app: "Workspace",
                name: "file-\(spec.operation.rawValue)",
                action: "file-mutation",
                workspaceRoot: spec.workspaceRoot,
                workspaceRelativePath: spec.path,
                postconditions: []
            )
        case .ui(let action):
            return ActionIntent(
                agentKind: .os,
                app: action.app ?? "unknown",
                name: action.name,
                action: action.name,
                query: action.query,
                text: action.text,
                role: action.role,
                domID: action.domID,
                x: action.x,
                y: action.y,
                button: action.button,
                count: action.count,
                modifiers: action.modifiers,
                amount: action.amount,
                windowTitle: action.windowTitle,
                clear: action.clear,
                width: action.width,
                height: action.height,
                postconditions: []
            )
        
        

case .code(let action):
            let codeCommand = commandSpec(for: action)
            return ActionIntent(
                agentKind: .code,
                app: action.app ?? "Workspace",
                name: action.name,
                action: action.name,
                query: action.query,
                text: action.patch,
                workspaceRoot: action.workspacePath,
                workspaceRelativePath: action.filePath,
                codeCommand: codeCommand,
                postconditions: []
            )
        }
    }

    private func surface(from source: String) -> RuntimeSurface {
        let lowered = source.lowercased()
        if lowered.contains("controller") { return .controller }
        if lowered.contains("recipe") { return .recipe }
        if lowered.contains("cli") { return .cli }
        return .mcp
    }

    public func evaluate(intent: ActionIntent, context: PolicyEvaluationContext) -> PolicyDecision {
        let activeMode = mode
        let appProtectionProfile = PolicyRules.appProtectionProfile(for: context.appName ?? intent.app)
        let classification = PolicyRules.classification(
            for: intent,
            context: context,
            appProtectionProfile: appProtectionProfile
        )
        let protectedOperation = classification.protectedOperation
        let riskLevel = classification.riskLevel

        // Repeated-action guard: block if the same protected operation fires
        // too many consecutive times without an intervening state change.
        if let op = protectedOperation, riskLevel != .blocked {
            cacheLock.lock()
            if lastProtectedOperation == op {
                consecutiveProtectedOpCount += 1
            } else {
                lastProtectedOperation = op
                consecutiveProtectedOpCount = 1
            }
            let tripped = consecutiveProtectedOpCount > maxConsecutiveProtectedOps
            cacheLock.unlock()

            if tripped {
                Log.warn("PolicyEngine: repeated-action guard tripped for \(op.rawValue) (\(consecutiveProtectedOpCount) consecutive)")
                return PolicyDecision(
                    allowed: false,
                    riskLevel: .blocked,
                    protectedOperation: op,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: true,
                    surface: context.surface,
                    policyMode: activeMode,
                    requiresApproval: false,
                    reason: "Repeated-action guard: \(op.rawValue) has fired \(consecutiveProtectedOpCount) consecutive times without a state change"
                )
            }
        }

        let baseDecision = PolicyDecision(
            allowed: riskLevel == .low,
            riskLevel: riskLevel,
            protectedOperation: protectedOperation,
            appProtectionProfile: appProtectionProfile,
            blockedByPolicy: riskLevel == .blocked,
            surface: context.surface,
            policyMode: activeMode,
            requiresApproval: riskLevel == .risky,
            reason: classification.reason ?? defaultReason(for: riskLevel, protectedOperation: protectedOperation, mode: activeMode)
        )

        switch activeMode {
        case .open:
            if riskLevel == .blocked {
                return baseDecision.withReason(baseDecision.reason ?? "Action blocked by policy")
            }
            return PolicyDecision(
                allowed: true,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: false,
                surface: context.surface,
                policyMode: activeMode,
                requiresApproval: false,
                reason: baseDecision.reason
            )

        case .confirmRisky:
            return baseDecision

        case .lockedDown:
            if riskLevel == .low {
                return PolicyDecision(
                    allowed: true,
                    riskLevel: riskLevel,
                    protectedOperation: protectedOperation,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: false,
                    surface: context.surface,
                    policyMode: activeMode,
                    requiresApproval: false,
                    reason: nil
                )
            }
            return PolicyDecision(
                allowed: false,
                riskLevel: riskLevel,
                protectedOperation: protectedOperation,
                appProtectionProfile: appProtectionProfile,
                blockedByPolicy: true,
                surface: context.surface,
                policyMode: activeMode,
                requiresApproval: false,
                reason: "Action blocked by locked-down policy"
            )

        case .adaptive:
            if riskLevel == .low {
                return PolicyDecision(
                    allowed: true,
                    riskLevel: riskLevel,
                    protectedOperation: protectedOperation,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: false,
                    surface: context.surface,
                    policyMode: activeMode,
                    requiresApproval: false,
                    reason: nil
                )
            }

            if riskLevel == .blocked || adaptiveModeBlocks(protectedOperation: protectedOperation) {
                return PolicyDecision(
                    allowed: false,
                    riskLevel: riskLevel,
                    protectedOperation: protectedOperation,
                    appProtectionProfile: appProtectionProfile,
                    blockedByPolicy: true,
                    surface: context.surface,
                    policyMode: activeMode,
                    requiresApproval: false,
                    reason: adaptiveBlockReason(for: protectedOperation)
                )
            }

            return baseDecision
        }
    }

    public static func defaultMode() -> PolicyMode {
        guard let raw = ProcessInfo.processInfo.environment["ORACLE_OS_POLICY_MODE"] else {
            return .confirmRisky
        }
        return PolicyMode(rawValue: raw) ?? .confirmRisky
    }

    private func defaultReason(
        for riskLevel: RiskLevel,
        protectedOperation: ProtectedOperation?,
        mode: PolicyMode
    ) -> String? {
        switch riskLevel {
        case .low:
            return nil
        case .risky:
            return "Action requires approval in \(mode.rawValue) mode"
        case .blocked:
            if let protectedOperation {
                return "Action blocked by policy: \(protectedOperation.rawValue)"
            }
            return "Action blocked by policy"
        }
    }

    private func adaptiveModeBlocks(protectedOperation: ProtectedOperation?) -> Bool {
        guard let protectedOperation else {
            return false
        }

        switch protectedOperation {
        case .send, .purchase, .delete, .uploadShare, .externalNetworkFetch, .gitPush, .destructiveVCS:
            return true
        default:
            return false
        }
    }

    private func adaptiveBlockReason(for protectedOperation: ProtectedOperation?) -> String {
        guard let protectedOperation else {
            return "Action blocked by adaptive policy"
        }

        switch protectedOperation {
        case .send, .purchase, .delete, .uploadShare:
            return "Action blocked by adaptive policy: irreversible UI risk"
        case .externalNetworkFetch:
            return "Action blocked by adaptive policy: remote network action"
        case .gitPush, .destructiveVCS:
            return "Action blocked by adaptive policy: external or destructive VCS action"
        default:
            return "Action blocked by adaptive policy"
        }
    }
}
