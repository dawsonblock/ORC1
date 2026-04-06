import Foundation

public struct RuntimeExecutionServices: @unchecked Sendable {
    public let planner: any Planner
    public let executor: VerifiedExecutor
    public let commitCoordinator: CommitCoordinator
    public let eventStore: any EventStore
    public let reducer: any EventReducer
    public let policyEngine: PolicyEngine
    public let processAdapter: any ProcessAdapter
    public let commandRouter: CommandRouter
    public let workspaceRunner: WorkspaceRunner
    public let repositoryIndexer: RepositoryIndexer
    public let approvalStore: ApprovalStore
    public let config: RuntimeConfig

    public init(
        planner: any Planner,
        executor: VerifiedExecutor,
        commitCoordinator: CommitCoordinator,
        eventStore: any EventStore,
        reducer: any EventReducer,
        policyEngine: PolicyEngine,
        processAdapter: any ProcessAdapter,
        commandRouter: CommandRouter,
        workspaceRunner: WorkspaceRunner,
        repositoryIndexer: RepositoryIndexer,
        approvalStore: ApprovalStore,
        config: RuntimeConfig
    ) {
        self.planner = planner
        self.executor = executor
        self.commitCoordinator = commitCoordinator
        self.eventStore = eventStore
        self.reducer = reducer
        self.policyEngine = policyEngine
        self.processAdapter = processAdapter
        self.commandRouter = commandRouter
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
        self.approvalStore = approvalStore
        self.config = config
    }
}

public struct RuntimeTracingServices: @unchecked Sendable {
    public let traceRecorder: TraceRecorder
    public let traceStore: ExperienceStore
    public let artifactWriter: FailureArtifactWriter
    public let metricsRecorder: MetricsRecorder

    public init(
        traceRecorder: TraceRecorder,
        traceStore: ExperienceStore,
        artifactWriter: FailureArtifactWriter,
        metricsRecorder: MetricsRecorder
    ) {
        self.traceRecorder = traceRecorder
        self.traceStore = traceStore
        self.artifactWriter = artifactWriter
        self.metricsRecorder = metricsRecorder
    }
}

public struct RuntimeKnowledgeServices: @unchecked Sendable {
    public let graphStore: GraphStore
    public let memoryStore: UnifiedMemoryStore
    public let stateMemoryIndex: StateMemoryIndex
    public let searchController: SearchController

    public init(
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        stateMemoryIndex: StateMemoryIndex,
        searchController: SearchController
    ) {
        self.graphStore = graphStore
        self.memoryStore = memoryStore
        self.stateMemoryIndex = stateMemoryIndex
        self.searchController = searchController
    }
}

public struct RuntimeDiagnosticsAdapters: @unchecked Sendable {
    public let automationHost: AutomationHost
    public let browserController: BrowserController
    public let browserPageStateBuilder: BrowserPageStateBuilder

    public init(
        automationHost: AutomationHost,
        browserController: BrowserController,
        browserPageStateBuilder: BrowserPageStateBuilder
    ) {
        self.automationHost = automationHost
        self.browserController = browserController
        self.browserPageStateBuilder = browserPageStateBuilder
    }
}

/// The authoritative runtime container.
/// All stateful runtime services must be created here once and shared.
/// Do NOT create competing instances of these services elsewhere.
@MainActor
public final class RuntimeContainer: @unchecked Sendable {
    // MARK: - Bundled live-path services
    public let execution: RuntimeExecutionServices
    public let tracing: RuntimeTracingServices
    public let knowledge: RuntimeKnowledgeServices
    public let diagnostics: RuntimeDiagnosticsAdapters

    // MARK: - Compatibility shims
    public var planner: any Planner { execution.planner }
    public var executor: VerifiedExecutor { execution.executor }
    public var commitCoordinator: CommitCoordinator { execution.commitCoordinator }
    public var eventStore: any EventStore { execution.eventStore }
    public var reducer: any EventReducer { execution.reducer }
    public var policyEngine: PolicyEngine { execution.policyEngine }
    public var processAdapter: any ProcessAdapter { execution.processAdapter }
    public var commandRouter: CommandRouter { execution.commandRouter }
    public var workspaceRunner: WorkspaceRunner { execution.workspaceRunner }
    public var repositoryIndexer: RepositoryIndexer { execution.repositoryIndexer }
    public var approvalStore: ApprovalStore { execution.approvalStore }
    public var config: RuntimeConfig { execution.config }
    public var traceRecorder: TraceRecorder { tracing.traceRecorder }
    public var traceStore: ExperienceStore { tracing.traceStore }
    public var artifactWriter: FailureArtifactWriter { tracing.artifactWriter }
    public var metricsRecorder: MetricsRecorder { tracing.metricsRecorder }
    public var graphStore: GraphStore { knowledge.graphStore }
    public var memoryStore: UnifiedMemoryStore { knowledge.memoryStore }
    public var stateMemoryIndex: StateMemoryIndex { knowledge.stateMemoryIndex }
    public var searchController: SearchController { knowledge.searchController }
    public var automationHost: AutomationHost { diagnostics.automationHost }
    public var browserController: BrowserController { diagnostics.browserController }
    public var browserPageStateBuilder: BrowserPageStateBuilder { diagnostics.browserPageStateBuilder }

    // MARK: - Peripheral Services
    public let stateAbstraction: StateAbstraction
    public let recoveryEngine: RecoveryEngine
    public let architectureEngine: ArchitectureEngine
    public let experimentManager: ExperimentManager
    public let criticLoop: CriticLoop
    public let stateAbstractionEngine: StateAbstractionEngine
    
    // MARK: - Recovery State
    public private(set) var recoveryReport: RecoveryReport?

    public init(
        planner: any Planner,
        executor: VerifiedExecutor,
        commitCoordinator: CommitCoordinator,
        eventStore: any EventStore,
        reducer: any EventReducer,
        policyEngine: PolicyEngine,
        processAdapter: any ProcessAdapter,
        commandRouter: CommandRouter,
        workspaceRunner: WorkspaceRunner,
        repositoryIndexer: RepositoryIndexer,
        config: RuntimeConfig,
        traceRecorder: TraceRecorder,
        traceStore: ExperienceStore,
        artifactWriter: FailureArtifactWriter,
        approvalStore: ApprovalStore,
        metricsRecorder: MetricsRecorder,
        graphStore: GraphStore,
        memoryStore: UnifiedMemoryStore,
        stateMemoryIndex: StateMemoryIndex,
        searchController: SearchController,
        stateAbstraction: StateAbstraction,
        recoveryEngine: RecoveryEngine,
        architectureEngine: ArchitectureEngine,
        experimentManager: ExperimentManager,
        criticLoop: CriticLoop,
        stateAbstractionEngine: StateAbstractionEngine,
        automationHost: AutomationHost,
        browserController: BrowserController,
        browserPageStateBuilder: BrowserPageStateBuilder
    ) {
        self.execution = RuntimeExecutionServices(
            planner: planner,
            executor: executor,
            commitCoordinator: commitCoordinator,
            eventStore: eventStore,
            reducer: reducer,
            policyEngine: policyEngine,
            processAdapter: processAdapter,
            commandRouter: commandRouter,
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer,
            approvalStore: approvalStore,
            config: config
        )
        self.tracing = RuntimeTracingServices(
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            metricsRecorder: metricsRecorder
        )
        self.knowledge = RuntimeKnowledgeServices(
            graphStore: graphStore,
            memoryStore: memoryStore,
            stateMemoryIndex: stateMemoryIndex,
            searchController: searchController
        )
        self.diagnostics = RuntimeDiagnosticsAdapters(
            automationHost: automationHost,
            browserController: browserController,
            browserPageStateBuilder: browserPageStateBuilder
        )
        self.stateAbstraction = stateAbstraction
        self.recoveryEngine = recoveryEngine
        self.architectureEngine = architectureEngine
        self.experimentManager = experimentManager
        self.criticLoop = criticLoop
        self.stateAbstractionEngine = stateAbstractionEngine
    }

    /// Records the recovery report after startup recovery completes.
    func recordRecovery(_ report: RecoveryReport) {
        self.recoveryReport = report
    }
}

/// Report returned by CommitCoordinator.recoverIfNeeded().
public struct RecoveryReport: Sendable, Equatable {
    public let didRecover: Bool
    public let walEntriesRecovered: Int
    public let eventsReplayed: Int
    public let rebuiltSnapshotID: UUID?
    public let completedAt: Date

    public init(
        didRecover: Bool,
        walEntriesRecovered: Int,
        eventsReplayed: Int,
        rebuiltSnapshotID: UUID?,
        completedAt: Date
    ) {
        self.didRecover = didRecover
        self.walEntriesRecovered = walEntriesRecovered
        self.eventsReplayed = eventsReplayed
        self.rebuiltSnapshotID = rebuiltSnapshotID
        self.completedAt = completedAt
    }

    public static let noRecoveryNeeded = RecoveryReport(
        didRecover: false,
        walEntriesRecovered: 0,
        eventsReplayed: 0,
        rebuiltSnapshotID: nil,
        completedAt: Date()
    )
}

/// Bundle returned by RuntimeBootstrap containing all runtime components.
/// This is the authoritative handle passed between surfaces. RuntimeContext is not used.
public struct BootstrappedRuntime: @unchecked Sendable {
    public let container: RuntimeContainer
    public let orchestrator: RuntimeOrchestrator
    public let recoveryReport: RecoveryReport

    public init(container: RuntimeContainer, orchestrator: RuntimeOrchestrator, recoveryReport: RecoveryReport) {
        self.container = container
        self.orchestrator = orchestrator
        self.recoveryReport = recoveryReport
    }
}

