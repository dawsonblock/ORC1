import Foundation

/// Protocol for providing world state snapshots to the execution boundary.
/// This enables preconditions validators to check current state before execution.
public protocol WorldStateProviding: Sendable {
    func snapshot() async -> WorldModelSnapshot
}

/// Adapter that provides world state via a closure — decoupled from any specific runtime authority.
public final class RuntimeWorldStateProvider: WorldStateProviding, @unchecked Sendable {
    private let getWorldState: @Sendable () async -> WorldStateModel

    public init(worldStateProvider: @escaping @Sendable () async -> WorldStateModel) {
        self.getWorldState = worldStateProvider
    }

    public func snapshot() async -> WorldModelSnapshot {
        let state = await getWorldState()
        return state.snapshot
    }
}
