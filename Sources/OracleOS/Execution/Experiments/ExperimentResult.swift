import Foundation

public enum ExperimentExecutionContext: String, Codable, Sendable, Equatable {
    case sandbox
}

public struct SandboxCleanupOutcome: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let removedWorktree: Bool
    public let removedBranch: Bool
    public let message: String?

    public init(
        succeeded: Bool,
        removedWorktree: Bool,
        removedBranch: Bool,
        message: String? = nil
    ) {
        self.succeeded = succeeded
        self.removedWorktree = removedWorktree
        self.removedBranch = removedBranch
        self.message = message
    }
}

public struct ExperimentSandboxEvidence: Codable, Sendable, Equatable {
    public let resolvedSandboxRoot: String
    public let canonicalWorkspaceRoot: String
    public let candidatePaths: [String]
    public let executedCommands: [String]
    public let cleanupOutcome: SandboxCleanupOutcome
    public let commitCoordinatorMutation: Bool
    public let approvalStorePromotion: Bool
    public let liveRuntimeStateMutation: Bool
    public let workspaceWritebackOutsideSandbox: Bool

    public init(
        resolvedSandboxRoot: String,
        canonicalWorkspaceRoot: String,
        candidatePaths: [String],
        executedCommands: [String],
        cleanupOutcome: SandboxCleanupOutcome,
        commitCoordinatorMutation: Bool = false,
        approvalStorePromotion: Bool = false,
        liveRuntimeStateMutation: Bool = false,
        workspaceWritebackOutsideSandbox: Bool = false
    ) {
        self.resolvedSandboxRoot = resolvedSandboxRoot
        self.canonicalWorkspaceRoot = canonicalWorkspaceRoot
        self.candidatePaths = candidatePaths
        self.executedCommands = executedCommands
        self.cleanupOutcome = cleanupOutcome
        self.commitCoordinatorMutation = commitCoordinatorMutation
        self.approvalStorePromotion = approvalStorePromotion
        self.liveRuntimeStateMutation = liveRuntimeStateMutation
        self.workspaceWritebackOutsideSandbox = workspaceWritebackOutsideSandbox
    }
}

public struct SandboxExecutionMetadata: Codable, Sendable, Equatable {
    public let canonicalWorkspaceRoot: String
    public let resolvedSandboxRoot: String
    public let candidateRelativePath: String
    public let attemptedPaths: [String]
    public let commandsRun: [String]
    public let cleanup: SandboxCleanupOutcome
}

public struct ExperimentResult: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let experimentID: String
    public let candidate: CandidatePatch
    public let executionContext: ExperimentExecutionContext
    public let committedToWorkspace: Bool
    public let sandboxPath: String
    public let commandResults: [CommandResult]
    public let diffSummary: String
    public let architectureRiskScore: Double
    public let architectureFindings: [ArchitectureFinding]
    public let refactorProposalID: String?
    public let selected: Bool
    public let promptDiagnostics: PromptDiagnostics?
    public let sandboxEvidence: ExperimentSandboxEvidence?
    public let sandboxMetadata: SandboxExecutionMetadata?

    public init(
        id: String = UUID().uuidString,
        experimentID: String,
        candidate: CandidatePatch,
        executionContext: ExperimentExecutionContext = .sandbox,
        committedToWorkspace: Bool = false,
        sandboxPath: String,
        commandResults: [CommandResult],
        diffSummary: String,
        architectureRiskScore: Double,
        architectureFindings: [ArchitectureFinding] = [],
        refactorProposalID: String? = nil,
        selected: Bool = false,
        promptDiagnostics: PromptDiagnostics? = nil,
        sandboxEvidence: ExperimentSandboxEvidence? = nil,
        sandboxMetadata: SandboxExecutionMetadata? = nil
    ) {
        self.id = id
        self.experimentID = experimentID
        self.candidate = candidate
        self.executionContext = executionContext
        self.committedToWorkspace = committedToWorkspace
        self.sandboxPath = sandboxPath
        self.commandResults = commandResults
        self.diffSummary = diffSummary
        self.architectureRiskScore = architectureRiskScore
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.selected = selected
        self.promptDiagnostics = promptDiagnostics
        self.sandboxEvidence = sandboxEvidence
        self.sandboxMetadata = sandboxMetadata
    }

    public var succeeded: Bool {
        commandResults.allSatisfy(\.succeeded)
    }

    public var elapsedMs: Double {
        commandResults.reduce(0) { $0 + $1.elapsedMs }
    }

    public func with(promptDiagnostics: PromptDiagnostics?) -> ExperimentResult {
        ExperimentResult(
            id: id,
            experimentID: experimentID,
            candidate: candidate,
            executionContext: executionContext,
            committedToWorkspace: committedToWorkspace,
            sandboxPath: sandboxPath,
            commandResults: commandResults,
            diffSummary: diffSummary,
            architectureRiskScore: architectureRiskScore,
            architectureFindings: architectureFindings,
            refactorProposalID: refactorProposalID,
            selected: selected,
            promptDiagnostics: promptDiagnostics,
            sandboxEvidence: sandboxEvidence,
            sandboxMetadata: sandboxMetadata
        )
    }
}
