import Foundation

actor MCPRuntimeHolder {
    private var bootstrappedRuntime: BootstrappedRuntime?
    private var runtimeContext: RuntimeContext?

    func getBootstrappedRuntime() async throws -> BootstrappedRuntime {
        if let existing = bootstrappedRuntime {
            return existing
        }
        let container = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .live())
        bootstrappedRuntime = container
        return container
    }

    func getRuntimeContext() async throws -> RuntimeContext {
        if let existing = runtimeContext {
            return existing
        }
        let bootstrapped = try await getBootstrappedRuntime()
        let ctx = RuntimeContext(container: bootstrapped.container)
        runtimeContext = ctx
        return ctx
    }
}
