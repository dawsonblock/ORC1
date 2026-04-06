import Foundation

@MainActor
public enum RuntimeBootstrap {

    // MARK: - Primary Entry Point

    /// Creates a fully bootstrapped runtime with recovery completed.
    ///
    /// This is the canonical runtime wiring for the supported execution path.
    /// It is the ONLY authorized way to create the bootstrapped runtime for
    /// main-path surfaces. Current callers:
    ///   - MCPRuntimeHost (oracle mcp → MCPServer → MCPDispatch → MCPRuntimeHost)
    ///   - ControllerRuntimeBridge (OracleController host)
    ///
    /// MCPDispatch remains the public MCP tool entrypoint, but reusable runtime
    /// lifecycle ownership lives in MCPRuntimeHost.
    ///
    /// CLI tooling exception: `oracle doctor` (Doctor.swift) and `oracle setup`
    /// (SetupWizard.swift) are standalone utilities that intentionally operate
    /// OUTSIDE this path. They construct DefaultProcessAdapter() directly and
    /// run without policy-checked orchestration. See their EXECUTION AUTHORITY
    /// NOTE comments for details.
    public static func makeBootstrappedRuntime(
        configuration: RuntimeConfig = .live()
    ) async throws -> BootstrappedRuntime {
        #if !os(macOS)
        preconditionFailure("OracleOS runtime build and test are supported on macOS 14+ only because the runtime depends on Apple accessibility frameworks and the vendored AX layer.")
        #endif

        let container = try makeContainer(configuration: configuration)

        // Run recovery BEFORE runtime becomes available
        let recoveryReport = try await container.commitCoordinator.recoverIfNeeded()
        container.recordRecovery(recoveryReport)

        // RuntimeContainer requires non-optional executor and commitCoordinator
        // inputs at construction time, so the supported authority chain has no
        // optional fallback or degraded bootstrap mode here.
        let orchestrator = RuntimeOrchestrator(container: container)

        return BootstrappedRuntime(
            container: container,
            orchestrator: orchestrator,
            recoveryReport: recoveryReport
        )
    }

    /// Synchronous bootstrap for contexts that cannot await.
    /// Recovery will be run on first use. Prefer async version.
    @available(*, unavailable, message: "Use async makeBootstrappedRuntime() instead across all surfaces")
    public static func makeDefault(configuration: RuntimeConfig) throws -> RuntimeContainer {
        return try makeContainer(configuration: configuration)
    }

    // MARK: - Internal Assembly
    
    /// Full container creation with all shared services.
    /// Core authority-chain services are assembled first; adjunct and
    /// experimental modules are available in the container but are not all part
    /// of the guaranteed main-path execution contract.
    private static func makeContainer(configuration: RuntimeConfig) throws -> RuntimeContainer {
        let rootURL = configuration.traceDirectory

        // Main-path authority chain foundations.
        // Create WAL first for crash safety.
        let wal = try CommitWAL(root: rootURL)
        let eventStore = try FileEventStore(root: rootURL)

        let compositeReducer = CompositeStateReducer(reducers: [
            MemoryStateReducer(),
            UIStateReducer(),
            RuntimeStateReducer(),
            ProjectStateReducer()
        ])

        // CommitCoordinator owns committed runtime state for the supported path.
        let commitCoordinator = CommitCoordinator(
            eventStore: eventStore,
            reducers: [compositeReducer],
            wal: wal
        )

        // Preconditions on the supported path read committed state through the
        // commit coordinator rather than through ad hoc runtime mutation.
        let stateProvider = RuntimeWorldStateProvider { [weak commitCoordinator] in
            await commitCoordinator?.currentState ?? WorldStateModel()
        }

        let policyEngine = PolicyEngine.shared
        let processAdapter = DefaultProcessAdapter(policyEngine: policyEngine)
        // Wire the shared process adapter into VisionBridge so sidecar startup
        // does not mint its own DefaultProcessAdapter locally.
        VisionBridge.configure(processAdapter: processAdapter)

        let workspaceRunner = WorkspaceRunner(processAdapter: processAdapter)
        let repositoryIndexer = RepositoryIndexer(processAdapter: processAdapter)

        let commandRouter = CommandRouter(
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer
        )

        // Approval, routing, verification, and planning remain the canonical
        // main-path execution chain.
        // Create ApprovalStore before the executor so it can be injected.
        let approvalStore = ApprovalStore(rootDirectory: configuration.approvalsDirectory)

        // Create executor with state provider and preconditions
        let executor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator(),
            stateProvider: stateProvider,
            approvalStore: approvalStore
        )

        let impactAnalyzer = RepositoryChangeImpactAnalyzer()
        let planner = MainPlanner(
            repositoryIndexer: repositoryIndexer,
            impactAnalyzer: impactAnalyzer
        )

        // Shared adjunct services created once for the live runtime.
        let traceRecorder = TraceRecorder()
        let traceStore = ExperienceStore()
        let artifactWriter = FailureArtifactWriter()
        // approvalStore is already created above and passed to the executor.
        let metricsRecorder = MetricsRecorder()
        
        // Shared stateful read-side and analysis services.
        let graphStore = GraphStore()
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let stateMemoryIndex = StateMemoryIndex()
        let searchController = SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: stateMemoryIndex,
                graphStore: graphStore
            )
        )
        
        // Optional or experimental modules. These may be present in the
        // container without being part of the guaranteed main-path authority
        // chain described in the public contract.
        let stateAbstraction = StateAbstraction()
        let recoveryEngine = RecoveryEngine()
        let architectureEngine = ArchitectureEngine()
        let parallelRunner = ParallelRunner(
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer
        )
        let patchRanker = PatchRanker(comparator: ResultComparator())
        let experimentManager = ExperimentManager(
            runner: parallelRunner,
            ranker: patchRanker,
            repositoryIndexer: repositoryIndexer
        )
        let criticLoop = CriticLoop()
        let stateAbstractionEngine = StateAbstractionEngine()
        
        // External adapters and observational helpers.
        let automationHost = AutomationHost.live()
        let browserController = BrowserController()
        let browserPageStateBuilder = BrowserPageStateBuilder(controller: browserController)

        return RuntimeContainer(
            planner: planner,
            executor: executor,
            commitCoordinator: commitCoordinator,
            eventStore: eventStore,
            reducer: compositeReducer,
            policyEngine: policyEngine,
            processAdapter: processAdapter,
            commandRouter: commandRouter,
            workspaceRunner: workspaceRunner,
            repositoryIndexer: repositoryIndexer,
            config: configuration,
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            approvalStore: approvalStore,
            metricsRecorder: metricsRecorder,
            graphStore: graphStore,
            memoryStore: memoryStore,
            stateMemoryIndex: stateMemoryIndex,
            searchController: searchController,
            stateAbstraction: stateAbstraction,
            recoveryEngine: recoveryEngine,
            architectureEngine: architectureEngine,
            experimentManager: experimentManager,
            criticLoop: criticLoop,
            stateAbstractionEngine: stateAbstractionEngine,
            automationHost: automationHost,
            browserController: browserController,
            browserPageStateBuilder: browserPageStateBuilder
        )
    }
}
