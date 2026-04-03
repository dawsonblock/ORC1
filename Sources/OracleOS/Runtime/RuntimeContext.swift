import Foundation

/// RuntimeContext: compile-time boundary guard — NOT a live runtime object.
///
/// NOT instantiated by any production code. Not used by RuntimeBootstrap,
/// RuntimeOrchestrator, MCPDispatch, or ControllerRuntimeBridge.
///
/// This class exists for two reasons only:
///
///   1. **Compile-time guards:** The `@available(*, unavailable)` extensions below
///      prevent policyEngine, workspaceRunner, and repositoryIndexer from ever being
///      added to a context-like convenience object. These are execution-adjacent services
///      that must remain in RuntimeContainer, not a read-side facade.
///
///   2. **Governance test scan target:** Tests in ExecutionBoundaryEnforcementTests
///      scan this file to confirm the forbidden properties remain absent and that the
///      compile-time guards remain in place.
///
/// The definitive runtime authority is:
///   RuntimeContainer → VerifiedExecutor → CommitCoordinator
///
/// Do NOT add properties, methods, or an initializer here. The class body is
/// intentionally empty. Consumers needing access to runtime services should hold
/// a reference to RuntimeContainer directly.
@MainActor
public final class RuntimeContext {}

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
