import Foundation

/// Owns MCP runtime bootstrap and reuse semantics for the current host process.
/// MCPDispatch stays a thin entrypoint and delegates lifecycle decisions here.
@MainActor
final class MCPRuntimeHost {
    typealias Bootstrapper = () async throws -> BootstrappedRuntime

    private let bootstrap: Bootstrapper
    private var cachedRuntime: BootstrappedRuntime?

    init(bootstrap: @escaping Bootstrapper = {
        try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .live())
    }) {
        self.bootstrap = bootstrap
    }

    /// Compatibility convenience for MCP surfaces that still expect eager
    /// project-memory binding. The shared runtime planner path now resolves
    /// workspace roots per intent inside RuntimeOrchestrator.
    func runtime(currentWorkspaceRoot: String) async throws -> BootstrappedRuntime {
        let runtime = try await runtime()
        runtime.container.memoryStore.setWorkspaceRoot(currentWorkspaceRoot)
        return runtime
    }

    func runtime() async throws -> BootstrappedRuntime {
        if let cachedRuntime {
            return cachedRuntime
        }

        let builtRuntime = try await bootstrap()
        cachedRuntime = builtRuntime
        return builtRuntime
    }

    var existingRuntime: BootstrappedRuntime? {
        cachedRuntime
    }

    func reset() {
        cachedRuntime = nil
    }
}