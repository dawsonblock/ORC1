import Foundation

public struct TraceSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let stepCount: Int
    public let lastUpdated: Date?

    public init(id: String, stepCount: Int, lastUpdated: Date?) {
        self.id = id
        self.stepCount = stepCount
        self.lastUpdated = lastUpdated
    }
}

public struct TraceStepViewModel: Codable, Sendable, Equatable, Identifiable {
    public let sessionID: String
    public let stepID: Int
    public let timestamp: Date
    public let toolName: String?
    public let actionName: String
    public let actionTarget: String?
    public let actionText: String?
    public let selectedElementID: String?
    public let selectedElementLabel: String?
    public let candidateScore: Double?
    public let candidateReasons: [String]
    public let preObservationHash: String?
    public let postObservationHash: String?
    public let postcondition: String?
    public let verified: Bool
    public let success: Bool
    public let failureClass: String?
    public let surface: String?
    public let policyMode: String?
    public let protectedOperation: String?
    public let approvalRequestID: String?
    public let approvalOutcome: String?
    public let blockedByPolicy: Bool
    public let appProfile: String?
    public let agentKind: String?
    public let domain: String?
    public let plannerFamily: String?
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let commandSummary: String?
    public let repositorySnapshotID: String?
    public let buildResultSummary: String?
    public let testResultSummary: String?
    public let patchID: String?
    public let projectMemoryRefs: [String]
    public let experimentID: String?
    public let candidateID: String?
    public let sandboxPath: String?
    public let selectedCandidate: Bool?
    public let experimentOutcome: String?
    public let architectureFindings: [String]
    public let refactorProposalID: String?
    public let knowledgeTier: String?
    public let elapsedMs: Double
    public let screenshotPath: String?
    public let artifactPaths: [String]
    public let notes: String?

    public var id: String { "\(sessionID)-\(stepID)" }

    public init(
        sessionID: String,
        stepID: Int,
        timestamp: Date,
        toolName: String?,
        actionName: String,
        actionTarget: String?,
        actionText: String?,
        selectedElementID: String?,
        selectedElementLabel: String?,
        candidateScore: Double?,
        candidateReasons: [String],
        preObservationHash: String?,
        postObservationHash: String?,
        postcondition: String?,
        verified: Bool,
        success: Bool,
        failureClass: String?,
        surface: String? = nil,
        policyMode: String? = nil,
        protectedOperation: String? = nil,
        approvalRequestID: String? = nil,
        approvalOutcome: String? = nil,
        blockedByPolicy: Bool = false,
        appProfile: String? = nil,
        agentKind: String? = nil,
        domain: String? = nil,
        plannerFamily: String? = nil,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        commandSummary: String? = nil,
        repositorySnapshotID: String? = nil,
        buildResultSummary: String? = nil,
        testResultSummary: String? = nil,
        patchID: String? = nil,
        projectMemoryRefs: [String] = [],
        experimentID: String? = nil,
        candidateID: String? = nil,
        sandboxPath: String? = nil,
        selectedCandidate: Bool? = nil,
        experimentOutcome: String? = nil,
        architectureFindings: [String] = [],
        refactorProposalID: String? = nil,
        knowledgeTier: String? = nil,
        elapsedMs: Double,
        screenshotPath: String?,
        artifactPaths: [String],
        notes: String?
    ) {
        self.sessionID = sessionID
        self.stepID = stepID
        self.timestamp = timestamp
        self.toolName = toolName
        self.actionName = actionName
        self.actionTarget = actionTarget
        self.actionText = actionText
        self.selectedElementID = selectedElementID
        self.selectedElementLabel = selectedElementLabel
        self.candidateScore = candidateScore
        self.candidateReasons = candidateReasons
        self.preObservationHash = preObservationHash
        self.postObservationHash = postObservationHash
        self.postcondition = postcondition
        self.verified = verified
        self.success = success
        self.failureClass = failureClass
        self.surface = surface
        self.policyMode = policyMode
        self.protectedOperation = protectedOperation
        self.approvalRequestID = approvalRequestID
        self.approvalOutcome = approvalOutcome
        self.blockedByPolicy = blockedByPolicy
        self.appProfile = appProfile
        self.agentKind = agentKind
        self.domain = domain
        self.plannerFamily = plannerFamily
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.commandSummary = commandSummary
        self.repositorySnapshotID = repositorySnapshotID
        self.buildResultSummary = buildResultSummary
        self.testResultSummary = testResultSummary
        self.patchID = patchID
        self.projectMemoryRefs = projectMemoryRefs
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.sandboxPath = sandboxPath
        self.selectedCandidate = selectedCandidate
        self.experimentOutcome = experimentOutcome
        self.architectureFindings = architectureFindings
        self.refactorProposalID = refactorProposalID
        self.knowledgeTier = knowledgeTier
        self.elapsedMs = elapsedMs
        self.screenshotPath = screenshotPath
        self.artifactPaths = artifactPaths
        self.notes = notes
    }
}

public struct TraceSessionDetail: Codable, Sendable, Equatable {
    public let summary: TraceSessionSummary
    public let steps: [TraceStepViewModel]

    public init(summary: TraceSessionSummary, steps: [TraceStepViewModel]) {
        self.summary = summary
        self.steps = steps
    }
}

public struct RecipeRunStepResult: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let action: String
    public let success: Bool
    public let durationMs: Int
    public let error: String?
    public let note: String?

    public init(id: Int, action: String, success: Bool, durationMs: Int, error: String? = nil, note: String? = nil) {
        self.id = id
        self.action = action
        self.success = success
        self.durationMs = durationMs
        self.error = error
        self.note = note
    }
}

public struct RecipeRunResultDocument: Codable, Sendable, Equatable {
    public let recipeName: String
    public let success: Bool
    public let stepsCompleted: Int
    public let totalSteps: Int
    public let error: String?
    public let traceSessionID: String?
    public let stepResults: [RecipeRunStepResult]
    public let paused: Bool
    public let pendingApprovalRequestID: String?
    public let resumeToken: String?

    public init(
        recipeName: String,
        success: Bool,
        stepsCompleted: Int,
        totalSteps: Int,
        error: String? = nil,
        traceSessionID: String? = nil,
        stepResults: [RecipeRunStepResult],
        paused: Bool = false,
        pendingApprovalRequestID: String? = nil,
        resumeToken: String? = nil
    ) {
        self.recipeName = recipeName
        self.success = success
        self.stepsCompleted = stepsCompleted
        self.totalSteps = totalSteps
        self.error = error
        self.traceSessionID = traceSessionID
        self.stepResults = stepResults
        self.paused = paused
        self.pendingApprovalRequestID = pendingApprovalRequestID
        self.resumeToken = resumeToken
    }

    public var statusLabel: String {
        if paused {
            return "Awaiting Approval"
        }
        return success ? "Succeeded" : "Failed"
    }

    public var summaryText: String {
        if paused {
            return "Recipe awaiting approval before execution continues."
        }
        if success {
            return "Recipe completed."
        }
        return error ?? "Recipe failed."
    }

    public func rejectedApprovalResult(message: String = "Recipe approval was rejected.") -> RecipeRunResultDocument {
        RecipeRunResultDocument(
            recipeName: recipeName,
            success: false,
            stepsCompleted: stepsCompleted,
            totalSteps: totalSteps,
            error: message,
            traceSessionID: traceSessionID,
            stepResults: stepResults,
            paused: false,
            pendingApprovalRequestID: nil,
            resumeToken: nil
        )
    }
}

public struct DashboardBootstrap: Codable, Sendable, Equatable {
    public let session: ControllerSession
    public let snapshot: ControlSnapshot?
    public let health: HealthStatus
    public let recipes: [RecipeDocument]
    public let traceSessions: [TraceSessionSummary]
    public let approvals: [ApprovalRequestDocument]
    public let missionControl: MissionControlSnapshot?
    public let chatConversation: ChatConversation?
    public let chatProviderStatus: ChatProviderStatus?

    public init(
        session: ControllerSession,
        snapshot: ControlSnapshot?,
        health: HealthStatus,
        recipes: [RecipeDocument],
        traceSessions: [TraceSessionSummary],
        approvals: [ApprovalRequestDocument],
        missionControl: MissionControlSnapshot? = nil,
        chatConversation: ChatConversation? = nil,
        chatProviderStatus: ChatProviderStatus? = nil
    ) {
        self.session = session
        self.snapshot = snapshot
        self.health = health
        self.recipes = recipes
        self.traceSessions = traceSessions
        self.approvals = approvals
        self.missionControl = missionControl
        self.chatConversation = chatConversation
        self.chatProviderStatus = chatProviderStatus
    }
}