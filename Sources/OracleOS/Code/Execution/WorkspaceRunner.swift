import Foundation

public enum WorkspaceRunnerError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedCommand(String)
    case scopeViolation(String)
    case forbiddenGitOperation(String)
    case networkNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedCommand(summary):
            "Unsupported command: \(summary)"
        case let .scopeViolation(message):
            message
        case let .forbiddenGitOperation(detail):
            "Forbidden git operation: \(detail)"
        case let .networkNotAllowed(detail):
            "Network access not allowed: \(detail)"
        }
    }
}

/// Classifies git subcommands by their access level.
public enum GitAccessLevel: Sendable {
    /// Read-only operations that never mutate the repo or touch the network.
    case readOnly
    /// Local write operations that mutate the working tree or index but do not contact remotes.
    case localWrite
    /// Network operations that contact remote servers.
    case network
}

public final class WorkspaceRunner: @unchecked Sendable {
    private let processAdapter: any ProcessAdapter

    public init(processAdapter: any ProcessAdapter) {
        self.processAdapter = processAdapter
    }

    // MARK: - Typed Command Execution (Phase 1 refactoring)

    /// Execute a build command with typed spec.
    public func runBuild(_ spec: BuildSpec) async throws -> ProcessResult {
        let args = buildArgs(spec)
        return try await executeProcess(
            executable: "/usr/bin/swift",
            arguments: args,
            workspace: spec.workspaceRoot
        )
    }

    /// Execute a test command with typed spec.
    public func runTest(_ spec: TestSpec) async throws -> ProcessResult {
        let args = testArgs(spec)
        return try await executeProcess(
            executable: "/usr/bin/swift",
            arguments: args,
            workspace: spec.workspaceRoot
        )
    }

    /// Execute a git command with typed spec.
    public func runGit(_ spec: GitSpec) async throws -> ProcessResult {
        // Validate git policy
        let args = [spec.operation.rawValue] + spec.args
        
        // Ensure git operation is allowed
        guard let _ = Self.gitSubcommandPolicy[spec.operation.rawValue] else {
            throw WorkspaceRunnerError.forbiddenGitOperation(
                "git subcommand '\(spec.operation.rawValue)' is not allowed"
            )
        }

        return try await executeProcess(
            executable: "/usr/bin/git",
            arguments: args,
            workspace: spec.workspaceRoot
        )
    }

    /// Apply a file mutation with typed spec.
    public func applyFile(_ spec: FileMutationSpec) async throws {
        let url = URL(fileURLWithPath: spec.path)
        
        switch spec.operation {
        case .write:
            guard let content = spec.content else {
                throw NSError(domain: "FileMutation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Write operation requires content"])
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            
        case .delete:
            try FileManager.default.removeItem(at: url)
            
        case .append:
            guard let content = spec.content else {
                throw NSError(domain: "FileMutation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Append operation requires content"])
            }
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try (existing + content).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Helper Methods

    private func buildArgs(_ spec: BuildSpec) -> [String] {
        var args = ["build"]
        if let scheme = spec.scheme {
            args.append(contentsOf: ["-scheme", scheme])
        }
        if let config = spec.configuration {
            args.append(contentsOf: ["-configuration", config])
        }
        if let dest = spec.destination {
            args.append(contentsOf: ["-destination", dest])
        }
        args.append(contentsOf: spec.extraArgs)
        return args
    }

    private func testArgs(_ spec: TestSpec) -> [String] {
        var args = ["test"]
        if let scheme = spec.scheme {
            args.append(contentsOf: ["-scheme", scheme])
        }
        if let filter = spec.filter {
            args.append(contentsOf: ["-testNamePattern", filter])
        }
        if spec.failureOnly {
            args.append("-failureOnly")
        }
        args.append(contentsOf: spec.extraArgs)
        return args
    }

    private func executeProcess(
        executable: String,
        arguments: [String],
        workspace: String
    ) async throws -> ProcessResult {
        let systemCommand = SystemCommand(executable: executable, arguments: arguments)
        let workspaceContext = WorkspaceContext(rootURL: URL(fileURLWithPath: workspace, isDirectory: true))
        let policy = CommandExecutionPolicy(timeoutSeconds: 300, maxOutputBytes: 100 * 1024 * 1024)
        
        return try await processAdapter.run(systemCommand, in: workspaceContext, policy: policy)
    }

    // MARK: - Legacy CommandSpec-based execution (for backwards compatibility)
    private func policy(for category: CodeCommandCategory) -> CommandExecutionPolicy {
        switch category {
        case .build, .test, .gitPush:
            // High timeout, high output byte limit for intensive commands
            return CommandExecutionPolicy(timeoutSeconds: 300, maxOutputBytes: 100 * 1024 * 1024)
        case .indexRepository, .searchCode, .generatePatch, .formatter, .linter, .parseBuildFailure, .parseTestFailure:
            // Medium timeout for tooling
            return CommandExecutionPolicy(timeoutSeconds: 60, maxOutputBytes: 10 * 1024 * 1024)
        case .openFile, .editFile, .writeFile, .gitStatus, .gitBranch, .gitCommit:
            // Quick local operations
            return CommandExecutionPolicy(timeoutSeconds: 15, maxOutputBytes: 1 * 1024 * 1024)
        }
    }

    public func execute(spec: CommandSpec) async throws -> CommandResult {
        guard isAllowed(spec) else {
            throw WorkspaceRunnerError.unsupportedCommand(spec.summary)
        }

        try validateGitPolicy(spec)

        // Derive network access from the command structure rather than trusting
        // the touchesNetwork field on CommandSpec.
        if derivedTouchesNetwork(spec) {
            throw WorkspaceRunnerError.networkNotAllowed(
                "Command \(spec.category.rawValue) requires network access which is not permitted"
            )
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: spec.workspaceRoot, isDirectory: true))
        _ = try scope.resolve(relativePath: spec.workspaceRelativePath)

        let start = Date()
        let systemCommand = SystemCommand(executable: spec.executable, arguments: spec.arguments)
        let workspaceContext = WorkspaceContext(rootURL: scope.rootURL)
        let execPolicy = policy(for: spec.category)
        let processResult = try await processAdapter.run(systemCommand, in: workspaceContext, policy: execPolicy)

        return CommandResult(
            succeeded: processResult.exitCode == 0,
            exitCode: processResult.exitCode,
            stdout: processResult.stdout,
            stderr: processResult.stderr,
            elapsedMs: Date().timeIntervalSince(start) * 1000.0,
            workspaceRoot: spec.workspaceRoot,
            category: spec.category,
            summary: spec.summary
        )
    }

    // MARK: - Git Subcommand Policy

    /// Allowed git subcommands and their access levels. Subcommands not in this
    /// map are rejected.
    static let gitSubcommandPolicy: [String: GitAccessLevel] = [
        "status": .readOnly,
        "log": .readOnly,
        "diff": .readOnly,
        "show": .readOnly,
        "branch": .readOnly,
        "rev-parse": .readOnly,
        "ls-files": .readOnly,
        "blame": .readOnly,
        "stash": .localWrite,
        "add": .localWrite,
        "commit": .localWrite,
        "checkout": .localWrite,
        "switch": .localWrite,
        "merge": .localWrite,
        "rebase": .localWrite,
        "reset": .localWrite,
        "restore": .localWrite,
        "tag": .localWrite,
        "push": .network,
        "pull": .network,
        "fetch": .network,
        "clone": .network,
        "remote": .network,
    ]

    /// Flags that are never allowed on any git subcommand.
    static let forbiddenGitFlags: Set<String> = [
        "--force", "-f",
        "--force-with-lease",
        "--mirror",
        "--bare",
        "--delete",
        "--prune-tags",
    ]

    /// Parse the git subcommand from arguments (skipping global flags like -C, -c).
    static func parseGitSubcommand(from arguments: [String]) -> String? {
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            // Skip global git flags that take a value
            if arg == "-C" || arg == "-c" || arg == "--git-dir" || arg == "--work-tree" {
                i += 2
                continue
            }
            // Skip global boolean flags
            if arg.hasPrefix("-") {
                i += 1
                continue
            }
            return arg
        }
        return nil
    }

    /// Validate that a git command conforms to the structured policy.
    private func validateGitPolicy(_ spec: CommandSpec) throws {
        guard spec.category.isGit else { return }

        guard let subcommand = Self.parseGitSubcommand(from: spec.arguments) else {
            throw WorkspaceRunnerError.forbiddenGitOperation("could not parse git subcommand")
        }

        guard Self.gitSubcommandPolicy[subcommand] != nil else {
            throw WorkspaceRunnerError.forbiddenGitOperation(
                "git subcommand '\(subcommand)' is not in the allowed set"
            )
        }

        // Check for forbidden flags
        for arg in spec.arguments where arg.hasPrefix("-") {
            // Treat an argument as forbidden if it:
            //  - exactly matches a forbidden flag (e.g. "--force-with-lease")
            //  - or starts with "<forbidden-flag>=" (e.g. "--force-with-lease=origin/main")
            //  - or, for single-character short flags (e.g. "-f"), appears in a combined
            //    short flag group (e.g. "-fn")
            for forbidden in Self.forbiddenGitFlags {
                if arg == forbidden || arg.hasPrefix(forbidden + "=") {
                    throw WorkspaceRunnerError.forbiddenGitOperation(
                        "flag '\(arg)' is forbidden on git commands"
                    )
                }

                // Handle combined short flags like "-fn" when "-f" is forbidden.
                if forbidden.hasPrefix("-"),
                   !forbidden.hasPrefix("--"),
                   forbidden.count == 2,
                   arg.hasPrefix("-"),
                   arg.count > 2 {
                    let shortFlagChar = forbidden.dropFirst()
                    if arg.dropFirst().contains(shortFlagChar) {
                        throw WorkspaceRunnerError.forbiddenGitOperation(
                            "flag '\(arg)' is forbidden on git commands"
                        )
                    }
                }
            }
        }
    }

    /// Derive whether a command touches the network from its structure, rather
    /// than trusting the `touchesNetwork` field on CommandSpec.
    func derivedTouchesNetwork(_ spec: CommandSpec) -> Bool {
        guard spec.category.isGit else { return false }
        guard let subcommand = Self.parseGitSubcommand(from: spec.arguments) else {
            return false
        }
        return Self.gitSubcommandPolicy[subcommand] == .network
    }

    private func isAllowed(_ spec: CommandSpec) -> Bool {
        switch spec.category {
        case .build, .test, .formatter, .linter, .gitStatus, .gitBranch, .gitCommit, .gitPush:
            return allowedExecutable(spec.executable)
        case .indexRepository, .searchCode, .openFile, .editFile, .writeFile, .generatePatch, .parseBuildFailure, .parseTestFailure:
            return true
        }
    }

    private func allowedExecutable(_ executable: String) -> Bool {
        let allowedExecutables = [
            "/usr/bin/env",
            "/usr/bin/git",
        ]
        return allowedExecutables.contains(executable)
    }

    private func sanitizedEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR", "DEVELOPER_DIR"]
        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            source[key].map { (key, $0) }
        })
    }
}
