import Foundation

public struct PermissionStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let granted: Bool
    public let detail: String?

    public init(id: String, title: String, granted: Bool, detail: String? = nil) {
        self.id = id
        self.title = title
        self.granted = granted
        self.detail = detail
    }
}

public struct StorageLocationStatus: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let path: String
    public let writable: Bool
    public let detail: String?

    public init(
        id: String,
        title: String,
        path: String,
        writable: Bool,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.writable = writable
        self.detail = detail
    }
}

public struct HealthStatus: Codable, Sendable, Equatable {
    public let updatedAt: Date
    public let runtimeVersion: String
    public let permissions: [PermissionStatus]
    public let claudeConfigured: Bool
    public let visionSidecarRunning: Bool
    public let visionSidecarVersion: String?
    public let visionModelPath: String?
    public let recipeDirectoryPath: String
    public let recipeCount: Int
    public let traceDirectoryPath: String
    public let applicationSupportPath: String
    public let approvalsDirectoryPath: String
    public let projectMemoryDirectoryPath: String
    public let experimentsDirectoryPath: String
    public let logsDirectoryPath: String
    public let graphDatabasePath: String
    public let storageLocations: [StorageLocationStatus]
    public let approvalBrokerActive: Bool
    public let controllerConnected: Bool
    public let policyMode: String
    public let runningFromAppBundle: Bool
    public let bundledHostAvailable: Bool
    public let bundledVisionBootstrapAvailable: Bool
    public let visionInstallPath: String
    public let buildVersion: String
    public let buildNumber: String

    public init(
        updatedAt: Date = Date(),
        runtimeVersion: String,
        permissions: [PermissionStatus],
        claudeConfigured: Bool,
        visionSidecarRunning: Bool,
        visionSidecarVersion: String? = nil,
        visionModelPath: String? = nil,
        recipeDirectoryPath: String,
        recipeCount: Int,
        traceDirectoryPath: String,
        applicationSupportPath: String,
        approvalsDirectoryPath: String,
        projectMemoryDirectoryPath: String,
        experimentsDirectoryPath: String,
        logsDirectoryPath: String,
        graphDatabasePath: String,
        storageLocations: [StorageLocationStatus],
        approvalBrokerActive: Bool,
        controllerConnected: Bool,
        policyMode: String,
        runningFromAppBundle: Bool,
        bundledHostAvailable: Bool,
        bundledVisionBootstrapAvailable: Bool,
        visionInstallPath: String,
        buildVersion: String,
        buildNumber: String
    ) {
        self.updatedAt = updatedAt
        self.runtimeVersion = runtimeVersion
        self.permissions = permissions
        self.claudeConfigured = claudeConfigured
        self.visionSidecarRunning = visionSidecarRunning
        self.visionSidecarVersion = visionSidecarVersion
        self.visionModelPath = visionModelPath
        self.recipeDirectoryPath = recipeDirectoryPath
        self.recipeCount = recipeCount
        self.traceDirectoryPath = traceDirectoryPath
        self.applicationSupportPath = applicationSupportPath
        self.approvalsDirectoryPath = approvalsDirectoryPath
        self.projectMemoryDirectoryPath = projectMemoryDirectoryPath
        self.experimentsDirectoryPath = experimentsDirectoryPath
        self.logsDirectoryPath = logsDirectoryPath
        self.graphDatabasePath = graphDatabasePath
        self.storageLocations = storageLocations
        self.approvalBrokerActive = approvalBrokerActive
        self.controllerConnected = controllerConnected
        self.policyMode = policyMode
        self.runningFromAppBundle = runningFromAppBundle
        self.bundledHostAvailable = bundledHostAvailable
        self.bundledVisionBootstrapAvailable = bundledVisionBootstrapAvailable
        self.visionInstallPath = visionInstallPath
        self.buildVersion = buildVersion
        self.buildNumber = buildNumber
    }

    public var storageIssues: [StorageLocationStatus] {
        storageLocations.filter { !$0.writable }
    }

    public var storageReady: Bool {
        storageIssues.isEmpty
    }
}

public struct ControllerGraphEdgeDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let actionContractID: String
    public let fromPlanningStateID: String
    public let toPlanningStateID: String
    public let agentKind: String
    public let domain: String
    public let workspaceRelativePath: String?
    public let commandCategory: String?
    public let plannerFamily: String?
    public let knowledgeTier: String
    public let attempts: Int
    public let successRate: Double
    public let averageLatencyMs: Double
    public let targetAmbiguityRate: Double
    public let rollingSuccessRate: Double
    public let recoveryTagged: Bool
    public let approvalRequired: Bool
    public let approvalOutcome: String?
    public let lastSuccessAt: Date?
    public let lastAttemptAt: Date?
    public let failureHistogram: [String: Int]
    public let promotionEligible: Bool

    public init(
        id: String,
        actionContractID: String,
        fromPlanningStateID: String,
        toPlanningStateID: String,
        agentKind: String,
        domain: String,
        workspaceRelativePath: String? = nil,
        commandCategory: String? = nil,
        plannerFamily: String? = nil,
        knowledgeTier: String,
        attempts: Int,
        successRate: Double,
        averageLatencyMs: Double,
        targetAmbiguityRate: Double,
        rollingSuccessRate: Double,
        recoveryTagged: Bool,
        approvalRequired: Bool,
        approvalOutcome: String? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        failureHistogram: [String: Int] = [:],
        promotionEligible: Bool
    ) {
        self.id = id
        self.actionContractID = actionContractID
        self.fromPlanningStateID = fromPlanningStateID
        self.toPlanningStateID = toPlanningStateID
        self.agentKind = agentKind
        self.domain = domain
        self.workspaceRelativePath = workspaceRelativePath
        self.commandCategory = commandCategory
        self.plannerFamily = plannerFamily
        self.knowledgeTier = knowledgeTier
        self.attempts = attempts
        self.successRate = successRate
        self.averageLatencyMs = averageLatencyMs
        self.targetAmbiguityRate = targetAmbiguityRate
        self.rollingSuccessRate = rollingSuccessRate
        self.recoveryTagged = recoveryTagged
        self.approvalRequired = approvalRequired
        self.approvalOutcome = approvalOutcome
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.failureHistogram = failureHistogram
        self.promotionEligible = promotionEligible
    }
}

public struct ControllerGraphDiagnostics: Codable, Sendable, Equatable {
    public let stableEdges: [ControllerGraphEdgeDiagnostics]
    public let candidateEdges: [ControllerGraphEdgeDiagnostics]
    public let recoveryEdges: [ControllerGraphEdgeDiagnostics]
    public let promotionEligibleCount: Int
    public let promotionsFrozen: Bool
    public let globalSuccessRate: Double

    public init(
        stableEdges: [ControllerGraphEdgeDiagnostics],
        candidateEdges: [ControllerGraphEdgeDiagnostics],
        recoveryEdges: [ControllerGraphEdgeDiagnostics],
        promotionEligibleCount: Int,
        promotionsFrozen: Bool,
        globalSuccessRate: Double
    ) {
        self.stableEdges = stableEdges
        self.candidateEdges = candidateEdges
        self.recoveryEdges = recoveryEdges
        self.promotionEligibleCount = promotionEligibleCount
        self.promotionsFrozen = promotionsFrozen
        self.globalSuccessRate = globalSuccessRate
    }
}

public struct ControllerWorkflowDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let goalPattern: String
    public let agentKind: String
    public let promotionStatus: String
    public let successRate: Double
    public let replayValidationSuccess: Double
    public let repeatedTraceSegmentCount: Int
    public let stepCount: Int
    public let parameterSlots: [String]
    public let sourceTraceRefs: [String]
    public let sourceGraphEdgeRefs: [String]
    public let stale: Bool

    public init(
        id: String,
        goalPattern: String,
        agentKind: String,
        promotionStatus: String,
        successRate: Double,
        replayValidationSuccess: Double,
        repeatedTraceSegmentCount: Int,
        stepCount: Int,
        parameterSlots: [String],
        sourceTraceRefs: [String],
        sourceGraphEdgeRefs: [String],
        stale: Bool
    ) {
        self.id = id
        self.goalPattern = goalPattern
        self.agentKind = agentKind
        self.promotionStatus = promotionStatus
        self.successRate = successRate
        self.replayValidationSuccess = replayValidationSuccess
        self.repeatedTraceSegmentCount = repeatedTraceSegmentCount
        self.stepCount = stepCount
        self.parameterSlots = parameterSlots
        self.sourceTraceRefs = sourceTraceRefs
        self.sourceGraphEdgeRefs = sourceGraphEdgeRefs
        self.stale = stale
    }
}

public struct ControllerExperimentCandidateDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let workspaceRelativePath: String
    public let hypothesis: String?
    public let selected: Bool
    public let executionContext: String
    public let committedToWorkspace: Bool
    public let succeeded: Bool
    public let architectureRiskScore: Double
    public let sandboxPath: String
    public let diffSummary: String
    public let buildSummary: String?
    public let testSummary: String?
    public let architectureFindings: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        workspaceRelativePath: String,
        hypothesis: String? = nil,
        selected: Bool,
        executionContext: String,
        committedToWorkspace: Bool,
        succeeded: Bool,
        architectureRiskScore: Double,
        sandboxPath: String,
        diffSummary: String,
        buildSummary: String? = nil,
        testSummary: String? = nil,
        architectureFindings: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.workspaceRelativePath = workspaceRelativePath
        self.hypothesis = hypothesis
        self.selected = selected
        self.executionContext = executionContext
        self.committedToWorkspace = committedToWorkspace
        self.succeeded = succeeded
        self.architectureRiskScore = architectureRiskScore
        self.sandboxPath = sandboxPath
        self.diffSummary = diffSummary
        self.buildSummary = buildSummary
        self.testSummary = testSummary
        self.architectureFindings = architectureFindings
    }
}

public struct ControllerExperimentDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let candidateCount: Int
    public let selectedCandidateID: String?
    public let winningSandboxPath: String?
    public let executionContext: String
    public let committedToWorkspace: Bool
    public let succeededCandidateCount: Int
    public let candidates: [ControllerExperimentCandidateDiagnostics]

    public init(
        id: String,
        candidateCount: Int,
        selectedCandidateID: String? = nil,
        winningSandboxPath: String? = nil,
        executionContext: String,
        committedToWorkspace: Bool,
        succeededCandidateCount: Int,
        candidates: [ControllerExperimentCandidateDiagnostics]
    ) {
        self.id = id
        self.candidateCount = candidateCount
        self.selectedCandidateID = selectedCandidateID
        self.winningSandboxPath = winningSandboxPath
        self.executionContext = executionContext
        self.committedToWorkspace = committedToWorkspace
        self.succeededCandidateCount = succeededCandidateCount
        self.candidates = candidates
    }
}

public struct ControllerRecoveryStrategyDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let attempts: Int
    public let successes: Int
    public let failures: Int
    public let failureHistogram: [String: Int]

    public init(
        id: String,
        attempts: Int,
        successes: Int,
        failures: Int,
        failureHistogram: [String: Int]
    ) {
        self.id = id
        self.attempts = attempts
        self.successes = successes
        self.failures = failures
        self.failureHistogram = failureHistogram
    }
}

public struct ControllerRecoveryDiagnostics: Codable, Sendable, Equatable {
    public let recoveryStepCount: Int
    public let strategies: [ControllerRecoveryStrategyDiagnostics]

    public init(recoveryStepCount: Int, strategies: [ControllerRecoveryStrategyDiagnostics]) {
        self.recoveryStepCount = recoveryStepCount
        self.strategies = strategies
    }
}

public struct ControllerProjectMemoryDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let kind: String
    public let knowledgeClass: String
    public let status: String
    public let path: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        kind: String,
        knowledgeClass: String,
        status: String,
        path: String,
        affectedModules: [String],
        evidenceRefs: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.kind = kind
        self.knowledgeClass = knowledgeClass
        self.status = status
        self.path = path
        self.affectedModules = affectedModules
        self.evidenceRefs = evidenceRefs
    }
}

public struct ControllerArchitectureFindingDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let severity: String
    public let affectedModules: [String]
    public let evidence: [String]
    public let riskScore: Double
    public let occurrences: Int
    public let governanceRuleID: String?

    public init(
        id: String,
        title: String,
        summary: String,
        severity: String,
        affectedModules: [String],
        evidence: [String],
        riskScore: Double,
        occurrences: Int,
        governanceRuleID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.severity = severity
        self.affectedModules = affectedModules
        self.evidence = evidence
        self.riskScore = riskScore
        self.occurrences = occurrences
        self.governanceRuleID = governanceRuleID
    }
}

public struct ControllerRepositoryIndexDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspaceRoot: String
    public let buildTool: String
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let indexedAt: Date
    public let fileCount: Int
    public let symbolCount: Int
    public let dependencyCount: Int
    public let callEdgeCount: Int
    public let testEdgeCount: Int
    public let buildTargetCount: Int
    public let topSymbols: [String]
    public let buildTargets: [String]
    public let topTests: [String]

    public init(
        id: String,
        workspaceRoot: String,
        buildTool: String,
        activeBranch: String?,
        isGitDirty: Bool,
        indexedAt: Date,
        fileCount: Int,
        symbolCount: Int,
        dependencyCount: Int,
        callEdgeCount: Int,
        testEdgeCount: Int,
        buildTargetCount: Int,
        topSymbols: [String],
        buildTargets: [String],
        topTests: [String]
    ) {
        self.id = id
        self.workspaceRoot = workspaceRoot
        self.buildTool = buildTool
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.indexedAt = indexedAt
        self.fileCount = fileCount
        self.symbolCount = symbolCount
        self.dependencyCount = dependencyCount
        self.callEdgeCount = callEdgeCount
        self.testEdgeCount = testEdgeCount
        self.buildTargetCount = buildTargetCount
        self.topSymbols = topSymbols
        self.buildTargets = buildTargets
        self.topTests = topTests
    }
}

public struct ControllerHostWindowDiagnostics: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appName: String
    public let title: String?
    public let elementCount: Int
    public let focused: Bool

    public init(
        id: String,
        appName: String,
        title: String? = nil,
        elementCount: Int,
        focused: Bool
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.elementCount = elementCount
        self.focused = focused
    }
}

public struct ControllerHostDiagnostics: Codable, Sendable, Equatable {
    public let snapshotID: String
    public let activeApplication: String?
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool
    public let windowCount: Int
    public let menuCount: Int
    public let dialogTitle: String?
    public let capturedWindowTitle: String?
    public let windows: [ControllerHostWindowDiagnostics]

    public init(
        snapshotID: String,
        activeApplication: String? = nil,
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool,
        windowCount: Int,
        menuCount: Int,
        dialogTitle: String? = nil,
        capturedWindowTitle: String? = nil,
        windows: [ControllerHostWindowDiagnostics]
    ) {
        self.snapshotID = snapshotID
        self.activeApplication = activeApplication
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.windowCount = windowCount
        self.menuCount = menuCount
        self.dialogTitle = dialogTitle
        self.capturedWindowTitle = capturedWindowTitle
        self.windows = windows
    }
}

public struct ControllerBrowserDiagnostics: Codable, Sendable, Equatable {
    public let appName: String
    public let available: Bool
    public let url: String?
    public let title: String?
    public let domain: String?
    public let indexedElementCount: Int
    public let topIndexedLabels: [String]
    public let simplifiedTextPreview: String?

    public init(
        appName: String,
        available: Bool,
        url: String? = nil,
        title: String? = nil,
        domain: String? = nil,
        indexedElementCount: Int,
        topIndexedLabels: [String],
        simplifiedTextPreview: String? = nil
    ) {
        self.appName = appName
        self.available = available
        self.url = url
        self.title = title
        self.domain = domain
        self.indexedElementCount = indexedElementCount
        self.topIndexedLabels = topIndexedLabels
        self.simplifiedTextPreview = simplifiedTextPreview
    }
}

public struct ControllerDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let graph: ControllerGraphDiagnostics
    public let workflows: [ControllerWorkflowDiagnostics]
    public let experiments: [ControllerExperimentDiagnostics]
    public let recovery: ControllerRecoveryDiagnostics
    public let projectMemory: [ControllerProjectMemoryDiagnostics]
    public let architectureFindings: [ControllerArchitectureFindingDiagnostics]
    public let repositoryIndexes: [ControllerRepositoryIndexDiagnostics]
    public let host: ControllerHostDiagnostics?
    public let browser: ControllerBrowserDiagnostics?

    public init(
        generatedAt: Date = Date(),
        graph: ControllerGraphDiagnostics,
        workflows: [ControllerWorkflowDiagnostics],
        experiments: [ControllerExperimentDiagnostics],
        recovery: ControllerRecoveryDiagnostics,
        projectMemory: [ControllerProjectMemoryDiagnostics],
        architectureFindings: [ControllerArchitectureFindingDiagnostics],
        repositoryIndexes: [ControllerRepositoryIndexDiagnostics],
        host: ControllerHostDiagnostics? = nil,
        browser: ControllerBrowserDiagnostics? = nil
    ) {
        self.generatedAt = generatedAt
        self.graph = graph
        self.workflows = workflows
        self.experiments = experiments
        self.recovery = recovery
        self.projectMemory = projectMemory
        self.architectureFindings = architectureFindings
        self.repositoryIndexes = repositoryIndexes
        self.host = host
        self.browser = browser
    }
}