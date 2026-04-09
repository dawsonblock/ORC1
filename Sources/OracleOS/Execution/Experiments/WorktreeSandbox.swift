// WorktreeSandbox.swift
//
// PRIVILEGED SIDE SUBSYSTEM — NOT on the main single execution path.
//
// WorktreeSandbox is called exclusively by ParallelRunner, which is invoked by
// ExperimentManager, which is dispatched directly from MCPDispatch for the
// `oracle_experiment_search` tool only.  It bypasses the main execution path
// (RuntimeOrchestrator → VerifiedExecutor → PolicyEngine) because experiment
// candidates run in isolated git worktrees and are evaluated, not committed.
//
// Do NOT route WorktreeSandbox through VerifiedExecutor. It is intentionally
// separate: the isolation guarantee comes from the worktree boundary, not from
// policy approval.
import Foundation

/// Typed errors for experiment sandbox containment enforcement.
/// These are the ONLY errors apply() can throw for boundary violations.
public enum SandboxError: Error, LocalizedError, Sendable {
    /// Path is absolute or contains a traversal sequence — rejected before canonicalization.
    case invalidRelativePath(String)
    /// Path resolves outside the sandbox root after canonicalization.
    case containmentViolation(path: String, sandboxRoot: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path):
            return "Candidate path '\(path)' is not a valid sandbox-relative path"
        case .containmentViolation(let path, let root):
            return "Candidate path '\(path)' resolves outside sandbox '\(root)'"
        }
    }
}

public struct WorktreeSandbox: Codable, Sendable, Equatable {
    public let experimentID: String
    public let candidateID: String
    public let workspaceRoot: String
    public let sandboxPath: String
    public let branchName: String

    public init(
        experimentID: String,
        candidateID: String,
        workspaceRoot: String,
        sandboxPath: String,
        branchName: String
    ) {
        self.experimentID = experimentID
        self.candidateID = candidateID
        self.workspaceRoot = workspaceRoot
        self.sandboxPath = sandboxPath
        self.branchName = branchName
    }

    public static func create(
        experimentID: String,
        candidateID: String,
        workspaceRoot: URL,
        experimentsRoot: URL,
        adapter: any ProcessAdapter
    ) throws -> WorktreeSandbox {
        try FileManager.default.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)
        let sandboxPath = experimentsRoot
            .appendingPathComponent(experimentID, isDirectory: true)
            .appendingPathComponent(candidateID, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let branchName = "codex/exp-\(experimentID)-\(candidateID)"
        try runGit(arguments: ["worktree", "add", "-f", "-b", branchName, sandboxPath.path, "HEAD"], workspaceRoot: workspaceRoot, adapter: adapter)

        return WorktreeSandbox(
            experimentID: experimentID,
            candidateID: candidateID,
            workspaceRoot: workspaceRoot.path,
            sandboxPath: sandboxPath.path,
            branchName: branchName
        )
    }

    public func apply(_ candidate: CandidatePatch) throws {
        let relativePath = candidate.workspaceRelativePath
        let pathComponents = relativePath.split(separator: "/")
        guard !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !pathComponents.contains(where: { $0 == "." || $0 == ".." }) else {
            throw SandboxError.invalidRelativePath(relativePath)
        }
        let candidateURL = URL(fileURLWithPath: sandboxPath, isDirectory: true)
            .appendingPathComponent(relativePath)
        let sandboxRootPath = canonicalSandboxRootPath()
        let resolvedRoot = URL(fileURLWithPath: sandboxRootPath, isDirectory: true)
        let resolvedURL = try canonicalCandidateTargetURL(
            candidateURL: candidateURL,
            sandboxRootURL: resolvedRoot,
            relativePath: relativePath
        )
        guard resolvedURL.path.hasPrefix(sandboxRootPath + "/") || resolvedURL.path == sandboxRootPath else {
            throw SandboxError.containmentViolation(path: relativePath, sandboxRoot: sandboxPath)
        }
        try FileManager.default.createDirectory(at: resolvedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try candidate.content.write(to: resolvedURL, atomically: true, encoding: .utf8)
    }

    public func diffSummary(using adapter: any ProcessAdapter) -> String {
        (try? runGitOutput(arguments: ["diff", "--stat"], workspaceRoot: URL(fileURLWithPath: sandboxPath, isDirectory: true), adapter: adapter)) ?? ""
    }

    public func cleanup(using adapter: any ProcessAdapter) {
        _ = cleanupOutcome(using: adapter)
    }

    public func cleanupOutcome(using adapter: any ProcessAdapter) -> SandboxCleanupOutcome {
        var removedWorktree = false
        var removedBranch = false
        var failures: [String] = []

        do {
            try runGit(
                arguments: ["worktree", "remove", "--force", sandboxPath],
                workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true),
                adapter: adapter
            )
            removedWorktree = true
        } catch {
            failures.append("worktree remove failed: \(error.localizedDescription)")
        }

        do {
            try runGit(
                arguments: ["branch", "-D", branchName],
                workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true),
                adapter: adapter
            )
            removedBranch = true
        } catch {
            failures.append("branch delete failed: \(error.localizedDescription)")
        }

        return SandboxCleanupOutcome(
            succeeded: failures.isEmpty,
            removedWorktree: removedWorktree,
            removedBranch: removedBranch,
            message: failures.isEmpty ? nil : failures.joined(separator: "; ")
        )
    }

    public func canonicalWorkspaceRootPath() -> String {
        URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    public func canonicalSandboxRootPath() -> String {
        URL(fileURLWithPath: sandboxPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func canonicalCandidateTargetURL(
        candidateURL: URL,
        sandboxRootURL: URL,
        relativePath: String
    ) throws -> URL {
        var current = sandboxRootURL
        let components = relativePath.split(separator: "/").map(String.init)
        for component in components {
            if component == "." || component == ".." || component.isEmpty {
                throw SandboxError.invalidRelativePath(relativePath)
            }
            current.appendPathComponent(component, isDirectory: false)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: current.path, isDirectory: &isDir) {
                let attrs = try FileManager.default.attributesOfItem(atPath: current.path)
                if let fileType = attrs[.type] as? FileAttributeType,
                   fileType == .typeSymbolicLink {
                    throw SandboxError.containmentViolation(path: relativePath, sandboxRoot: sandboxPath)
                }
            }
        }
        return candidateURL.standardizedFileURL
    }
}

private func runGit(arguments: [String], workspaceRoot: URL, adapter: any ProcessAdapter) throws {
    let context = WorkspaceContext(rootURL: workspaceRoot)
    let result = try adapter.runSync(SystemCommand(executable: "/usr/bin/env", arguments: ["git"] + arguments), in: context, policy: nil)
    guard result.exitCode == 0 else {
        throw NSError(domain: "WorktreeSandbox", code: Int(result.exitCode), userInfo: [
            NSLocalizedDescriptionKey: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
}

private func runGitOutput(arguments: [String], workspaceRoot: URL, adapter: any ProcessAdapter) throws -> String {
    let context = WorkspaceContext(rootURL: workspaceRoot)
    let result = try adapter.runSync(SystemCommand(executable: "/usr/bin/env", arguments: ["git"] + arguments), in: context, policy: nil)
    guard result.exitCode == 0 else {
        throw NSError(domain: "WorktreeSandbox", code: Int(result.exitCode), userInfo: [
            NSLocalizedDescriptionKey: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
    return result.stdout
}
