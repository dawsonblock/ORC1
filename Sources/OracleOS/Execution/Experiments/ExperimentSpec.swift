import Foundation

public struct ExperimentCommandRequest: Codable, Sendable, Equatable {
    public let category: CodeCommandCategory
    public let executable: String
    public let arguments: [String]
    public let summary: String

    public init(
        category: CodeCommandCategory,
        executable: String,
        arguments: [String],
        summary: String
    ) {
        self.category = category
        self.executable = executable
        self.arguments = arguments
        self.summary = summary
    }

    public func materializedForSandbox(workspaceRoot: String) -> CommandSpec {
        CommandSpec(
            category: category,
            executable: executable,
            arguments: arguments,
            workspaceRoot: workspaceRoot,
            summary: summary,
            mutatesWorkspace: false,
            touchesNetwork: false
        )
    }
}

public struct ExperimentSpec: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let goalDescription: String
    public let workspaceRoot: String
    public let candidates: [CandidatePatch]
    public let buildCommand: ExperimentCommandRequest?
    public let testCommand: ExperimentCommandRequest?
    public let promptDiagnostics: PromptDiagnostics?

    public init(
        id: String = UUID().uuidString,
        goalDescription: String,
        workspaceRoot: String,
        candidates: [CandidatePatch],
        buildCommand: ExperimentCommandRequest? = nil,
        testCommand: ExperimentCommandRequest? = nil,
        promptDiagnostics: PromptDiagnostics? = nil
    ) {
        self.id = id
        self.goalDescription = goalDescription
        self.workspaceRoot = workspaceRoot
        self.candidates = candidates
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.promptDiagnostics = promptDiagnostics
    }

    /// Returns a copy with candidates truncated to `ExperimentLimits.maxCandidates`.
    public func boundedByLimits() -> ExperimentSpec {
        let bounded = Array(candidates.prefix(ExperimentLimits.maxCandidates))
        guard bounded.count != candidates.count else { return self }
        return ExperimentSpec(
            id: id,
            goalDescription: goalDescription,
            workspaceRoot: workspaceRoot,
            candidates: bounded,
            buildCommand: buildCommand,
            testCommand: testCommand,
            promptDiagnostics: promptDiagnostics
        )
    }
}
