import Foundation

/// Persistent trace storage using JSONL format.
///
/// Traces store verified execution deltas, not bloated snapshots.
/// Large raw observations are written only when debug mode is active.
public final class ExperienceStore: @unchecked Sendable {
    public let directoryURL: URL

    private let encoder: JSONEncoder
    private let writeLock = NSLock()

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    public convenience init() {
        self.init(directoryURL: Self.resolveSessionsDirectory())
    }

    @discardableResult
    public func append(_ event: TraceEvent) throws -> URL {
        writeLock.lock()
        defer { writeLock.unlock() }

        let fileURL = directoryURL.appendingPathComponent("\(event.sessionID).jsonl")
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        return fileURL
    }

    public func loadRecentEvents(limit: Int = 1000) -> [TraceEvent] {
        writeLock.lock()
        defer { writeLock.unlock() }

        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }

        var files = [(URL, Date)]()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.creationDateKey])
            let date = values?.creationDate ?? Date.distantPast
            files.append((fileURL, date))
        }

        files.sort { $0.1 > $1.1 } // newest first

        var events = [TraceEvent]()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (fileURL, _) in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            
            let lines = content.split(separator: "\n")
            for line in lines.reversed() { // read lines bottom-up to keep newest first inside file, then reverse later
                guard let data = line.data(using: .utf8),
                      let event = try? decoder.decode(TraceEvent.self, from: data) else {
                    continue
                }
                events.append(event)
                if events.count >= limit {
                    return events.reversed() // order chronological
                }
            }
        }

        return events.reversed() // order chronological
    }

    public static func traceRootDirectory() -> URL {
        OracleProductPaths.tracesRootDirectory
    }

    public static func resolveSessionsDirectory() -> URL {
        traceRootDirectory().appendingPathComponent("sessions", isDirectory: true)
    }
}
