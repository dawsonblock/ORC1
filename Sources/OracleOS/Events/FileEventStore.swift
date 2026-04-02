import Foundation

public actor FileEventStore: EventStore {
    private let logURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var sequenceCounter: Int = 0

    public init(root: URL) throws {
        let eventsDir = root.appendingPathComponent("events", isDirectory: true)
        try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
        let logURL = eventsDir.appendingPathComponent("event-log.jsonl")
        self.logURL = logURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        
        let existing = try Self.loadAll(from: logURL)
        self.sequenceCounter = existing.map { $0.sequenceNumber }.max() ?? 0
    }

    public func append(_ envelope: EventEnvelope) throws {
        try append(contentsOf: [envelope])
    }
    
    public func append(contentsOf newEnvelopes: [EventEnvelope]) throws {
        var payload = Data()
        for env in newEnvelopes {
            payload.append(try encoder.encode(env))
            payload.append(contentsOf: [0x0A])
        }
        
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(payload)
        try handle.synchronize()
        fsync(handle.fileDescriptor)
    }

    private static func loadAll(from url: URL) throws -> [EventEnvelope] {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try data
            .split(separator: 0x0A)
            .map { try decoder.decode(EventEnvelope.self, from: Data($0)) }
    }

    private func _loadAll() throws -> [EventEnvelope] {
        return try Self.loadAll(from: logURL)
    }

    public func all() throws -> [EventEnvelope] {
        return try _loadAll()
    }

    public func events(forCommandID id: CommandID) throws -> [EventEnvelope] {
        return try _loadAll().filter { $0.commandID == id }
    }

    public func events(after sequenceNumber: Int) throws -> [EventEnvelope] {
        return try _loadAll().filter { $0.sequenceNumber > sequenceNumber }
    }

    public func nextSequenceNumber() -> Int {
        sequenceCounter += 1
        return sequenceCounter
    }
}
