import Foundation

/// In-memory snapshot store for session-level snapshot persistence.
/// NOTE: This implementation is session-only. Snapshots are not persisted across restarts.
/// For durable storage, replace with SQLite or append-only log backend.
public actor SnapshotStore {
    private let directory: URL
    private var snapshots: [StateSnapshot] = []
    private var store: [UUID: StateSnapshot] = [:]
    private let maxSnapshots: Int

    public init(directory: URL, maxSnapshots: Int = 100) {
        self.directory = directory
        self.maxSnapshots = maxSnapshots
    }

    public func persist(_ snapshot: StateSnapshot) throws {
        store[snapshot.id] = snapshot
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            let removed = snapshots.removeFirst()
            store.removeValue(forKey: removed.id)
        }
    }

    public func load(id: UUID) throws -> StateSnapshot {
        guard let snapshot = store[id] else {
            throw CocoaError(.fileNoSuchFile)
        }
        return snapshot
    }

    public func append(_ snapshot: StateSnapshot) {
        store[snapshot.id] = snapshot
        snapshots.append(snapshot)
        if snapshots.count > maxSnapshots {
            let removed = snapshots.removeFirst()
            store.removeValue(forKey: removed.id)
        }
    }

    public func latest() -> StateSnapshot? {
        snapshots.last
    }

    public func all() -> [StateSnapshot] {
        snapshots
    }

    public func snapshot(byID id: UUID) -> StateSnapshot? {
        store[id]
    }

    public func snapshot(atSequence sequenceNumber: Int) -> StateSnapshot? {
        snapshots.first(where: { $0.sequenceNumber == sequenceNumber })
    }

    public func clear() {
        snapshots.removeAll()
        store.removeAll()
    }

    public var count: Int {
        snapshots.count
    }
}
