import Foundation

public enum WorkspaceScopeError: Error, LocalizedError, Sendable, Equatable {
    case invalidRoot(String)
    case outsideWorkspace(String)
    case missingPath(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRoot(path):
            "Invalid workspace root: \(path)"
        case let .outsideWorkspace(path):
            "Path is outside workspace scope: \(path)"
        case let .missingPath(path):
            "Missing workspace path: \(path)"
        }
    }
}

public struct WorkspaceScope: Sendable, Equatable {
    public let rootURL: URL

    public init(rootURL: URL) throws {
        let standardized = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceScopeError.invalidRoot(standardized.path)
        }
        self.rootURL = standardized
    }

    public func resolve(relativePath: String?) throws -> URL? {
        guard let relativePath else { return nil }
        guard !relativePath.isEmpty else {
            throw WorkspaceScopeError.missingPath(relativePath)
        }

        let candidate: URL
        if relativePath.hasPrefix("/") {
            // Absolute path — check containment directly; do NOT append to root.
            candidate = URL(fileURLWithPath: relativePath).standardizedFileURL
        } else {
            // Relative path — appendingPathComponent + standardizedFileURL eliminates
            // any `../` traversal sequences before the containment check.
            candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        }

        // Require trailing slash on root so that /tmp/workspace-evil does not
        // match root /tmp/workspace.
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) || candidate.path == rootURL.path else {
            throw WorkspaceScopeError.outsideWorkspace(candidate.path)
        }
        return candidate
    }

    public func contains(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        return standardized.path.hasPrefix(rootPrefix) || standardized.path == rootURL.path
    }
}
