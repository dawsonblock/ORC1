import Foundation

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
        experimentsRoot: URL
    ) throws -> WorktreeSandbox {
        try FileManager.default.createDirectory(at: experimentsRoot, withIntermediateDirectories: true)
        let sandboxPath = experimentsRoot
            .appendingPathComponent(experimentID, isDirectory: true)
            .appendingPathComponent(candidateID, isDirectory: true)
        try FileManager.default.createDirectory(at: sandboxPath.deletingLastPathComponent(), withIntermediateDirectories: true)

        let branchName = "codex/exp-\(experimentID)-\(candidateID)"
        try runGit(arguments: ["worktree", "add", "-f", "-b", branchName, sandboxPath.path, "HEAD"], workspaceRoot: workspaceRoot)

        return WorktreeSandbox(
            experimentID: experimentID,
            candidateID: candidateID,
            workspaceRoot: workspaceRoot.path,
            sandboxPath: sandboxPath.path,
            branchName: branchName
        )
    }

    public func apply(_ candidate: CandidatePatch) throws {
        let fileURL = URL(fileURLWithPath: sandboxPath, isDirectory: true)
            .appendingPathComponent(candidate.workspaceRelativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try candidate.content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func diffSummary() -> String {
        (try? runGitOutput(arguments: ["diff", "--stat"], workspaceRoot: URL(fileURLWithPath: sandboxPath, isDirectory: true))) ?? ""
    }

    public func cleanup() {
        try? runGit(arguments: ["worktree", "remove", "--force", sandboxPath], workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
        try? runGit(arguments: ["branch", "-D", branchName], workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true))
    }
}

private func runGit(arguments: [String], workspaceRoot: URL) throws {
    let adapter = DefaultProcessAdapter()
    let context = WorkspaceContext(rootURL: workspaceRoot)
    let result = try adapter.runSync(SystemCommand(executable: "/usr/bin/env", arguments: ["git"] + arguments), in: context)
    guard result.exitCode == 0 else {
        throw NSError(domain: "WorktreeSandbox", code: Int(result.exitCode), userInfo: [
            NSLocalizedDescriptionKey: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
}

private func runGitOutput(arguments: [String], workspaceRoot: URL) throws -> String {
    let adapter = DefaultProcessAdapter()
    let context = WorkspaceContext(rootURL: workspaceRoot)
    let result = try adapter.runSync(SystemCommand(executable: "/usr/bin/env", arguments: ["git"] + arguments), in: context)
    guard result.exitCode == 0 else {
        throw NSError(domain: "WorktreeSandbox", code: Int(result.exitCode), userInfo: [
            NSLocalizedDescriptionKey: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }
    return result.stdout
}
