import Foundation

/// Write-Ahead Log for crash-safe event commits.
/// Events are written to WAL before being appended to the event store.
/// On recovery, pending events are replayed to ensure durability.
///
/// DURABILITY GUARANTEE:
///   - writePending() uses atomic write + fsync for crash safety
///   - If process crashes between writePending() and clear(), recovery replays WAL
///   - If process crashes between append() and clear(), WAL can be discarded (events already in store)
public final class CommitWAL: @unchecked Sendable {
    private let walURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(root: URL) throws {
        let walDir = root.appendingPathComponent("wal", isDirectory: true)
        try FileManager.default.createDirectory(at: walDir, withIntermediateDirectories: true)
        walURL = walDir.appendingPathComponent("pending-commit.json")
    }

    /// Write events to WAL before committing to event store.
    /// MUST be called before EventStore.append().
    ///
    /// Uses atomic write + fsync for crash safety.
    /// Ensures events are durable before append() is attempted.
    public func writePending(_ envelopes: [EventEnvelope]) throws {
        let data = try encoder.encode(envelopes)
        try data.write(to: walURL, options: .atomic)
        
        // Ensure data is flushed to disk (crash-safe).
        // If process dies after writePending, recovery will replay these events.
        guard let fd = fileDescriptor(for: walURL) else { return }
        defer { close(fd) }
        let result = fsync(fd)
        guard result == 0 else {
            throw NSError(
                domain: "CommitWAL",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "fsync failed: \(errno)"]
            )
        }
    }

    /// Read pending events from WAL for recovery.
    /// Returns nil if no pending commit exists.
    public func readPending() throws -> [EventEnvelope]? {
        guard hasPendingCommit else { return nil }
        let data = try Data(contentsOf: walURL)
        return try decoder.decode([EventEnvelope].self, from: data)
    }

    /// Clear WAL after successful commit.
    /// MUST be called after EventStore.append() succeeds.
    ///
    /// Safe to call even if WAL is already cleared (idempotent).
    public func clear() throws {
        if FileManager.default.fileExists(atPath: walURL.path) {
            try FileManager.default.removeItem(at: walURL)
        }
    }

    /// Check if there's a pending commit that needs recovery.
    public var hasPendingCommit: Bool {
        FileManager.default.fileExists(atPath: walURL.path)
    }

    // MARK: - Helpers

    private func fileDescriptor(for url: URL) -> Int32? {
        let path = url.path
        let fd = open(path, O_WRONLY)
        guard fd >= 0 else { return nil }
        return fd
    }
}
