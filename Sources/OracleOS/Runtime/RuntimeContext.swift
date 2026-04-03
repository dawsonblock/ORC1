import Foundation

/// RuntimeContext: boundary-guard facade — NOT instantiated in any live production code path.
///
/// This class is NOT created or used by RuntimeBootstrap, RuntimeOrchestrator, MCPDispatch,
/// ControllerRuntimeBridge, or any other live production path. Its sole live role is:
///
///   1. **Compile-time guards:** The `@available(*, unavailable)` extensions at the bottom of
///      this file prevent policyEngine, workspaceRunner, and repositoryIndexer from ever being
///      added back to a context-like object. These are the execution-adjacent services that must
///      remain in RuntimeContainer only.
///
///   2. **Enforcement test surface:** Governance tests in
///      `Tests/OracleOSTests/Governance/ExecutionBoundaryEnforcementTests.swift` scan this file
///      to confirm the forbidden properties remain absent and the `@available` guards remain present.
///
/// If you are building a read-side convenience wrapper over RuntimeContainer, do NOT extend
/// this class. Create a dedicated, narrow struct for your consumer instead.
///
/// The definitive runtime authority remains: RuntimeContainer → VerifiedExecutor → CommitCoordinator.
///
/// What this class would expose (if instantiated):
/// - Observability: traceRecorder, traceStore, artifactWriter, metricsRecorder, telemetry
/// - State stores: approvalStore, graphStore, memoryStore, stateAbstraction
/// - Analysis and evaluation: criticLoop, architectureEngine, recoveryEngine, experimentManager
/// - External adapters: automationHost (AX automation snapshots), browserController
/// - Index/search: stateMemoryIndex, searchController, stateAbstractionEngine
///
/// What is FORBIDDEN here (guarded by @available(*, unavailable)):
///   policyEngine, workspaceRunner, repositoryIndexer
/// These three own the policy-checked execution path and must remain in RuntimeContainer.
/// Do NOT add them back here.
@MainActor
public final class RuntimeContext {
    // MARK: - Configuration
    public let config: RuntimeConfig

    // MARK: - Tracing & Observability
    public let traceRecorder: TraceRecorder
    public let traceStore: ExperienceStore
    public let artifactWriter: FailureArtifactWriter
    public let metricsRecorder: MetricsRecorder
    public private(set) lazy var telemetry: RuntimeTelemetry = RuntimeTelemetry(container: self.container)

    // MARK: - Peripheral Services (not execution-critical)
    public let approvalStore: ApprovalStore
    public let graphStore: GraphStore
    public let memoryStore: UnifiedMemoryStore
    public let stateAbstraction: StateAbstraction
    public let recoveryEngine: RecoveryEngine
    public let architectureEngine: ArchitectureEngine
    public let experimentManager: ExperimentManager
    public let stateMemoryIndex: StateMemoryIndex
    public let searchController: SearchController
    public let criticLoop: CriticLoop
    public let stateAbstractionEngine: StateAbstractionEngine

    // MARK: - External Adapters (browser, automation)
    public let automationHost: AutomationHost
    public let browserController: BrowserController
    public let browserPageStateBuilder: BrowserPageStateBuilder

    // MARK: - Removed: Execution-Adjacent Services
    // policyEngine, workspaceRunner, repositoryIndexer were removed
    // These are execution-adjacent and must not live on a convenience facade.
    // Access them through RuntimeContainer directly.

    private let container: RuntimeContainer

    /// Primary initializer: creates RuntimeContext from a RuntimeContainer.
    /// This ensures all shared services come from the same authority.
    public init(
        container: RuntimeContainer
    ) {
        self.container = container
        // Pull shared services from container - single source of truth
        self.config = container.config
        self.traceRecorder = container.traceRecorder
        self.traceStore = container.traceStore
        self.artifactWriter = container.artifactWriter
        self.metricsRecorder = container.metricsRecorder
        self.approvalStore = container.approvalStore
        self.graphStore = container.graphStore
        self.memoryStore = container.memoryStore
        self.stateMemoryIndex = container.stateMemoryIndex
        self.searchController = container.searchController

        // Peripheral services that don't need sharing
        self.stateAbstraction = container.stateAbstraction
        self.recoveryEngine = container.recoveryEngine
        self.architectureEngine = container.architectureEngine
        self.experimentManager = container.experimentManager
        self.criticLoop = container.criticLoop
        self.stateAbstractionEngine = container.stateAbstractionEngine

        // External adapters
        self.automationHost = container.automationHost
        self.browserController = container.browserController
        self.browserPageStateBuilder = container.browserPageStateBuilder
    }
}

// MARK: - Compile-time guards against re-introducing execution authority leaks

@available(*, unavailable, message: "policyEngine is execution-adjacent and FORBIDDEN on RuntimeContext. Access through RuntimeContainer only.")
extension RuntimeContext {
    public var policyEngine: Never {
        fatalError("Attempted to access forbidden policyEngine on RuntimeContext")
    }
}

@available(*, unavailable, message: "workspaceRunner is execution-adjacent and FORBIDDEN on RuntimeContext. Access through RuntimeContainer only.")
extension RuntimeContext {
    public var workspaceRunner: Never {
        fatalError("Attempted to access forbidden workspaceRunner on RuntimeContext")
    }
}

@available(*, unavailable, message: "repositoryIndexer is execution-adjacent and FORBIDDEN on RuntimeContext. Access through RuntimeContainer only.")
extension RuntimeContext {
    public var repositoryIndexer: Never {
        fatalError("Attempted to access forbidden repositoryIndexer on RuntimeContext")
    }
}
