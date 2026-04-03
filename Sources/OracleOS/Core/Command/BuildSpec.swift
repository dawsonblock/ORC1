import Foundation

/// Typed build specification. No generic shell execution.
/// Fields limited to what `swift build` actually consumes.
/// Xcode-only concepts (`scheme`, `destination`) are not present.
public struct BuildSpec: Sendable, Codable {
    public let workspaceRoot: String
    /// Passed as `--configuration`. Nil uses SwiftPM default (Debug).
    public let configuration: String?
    /// Extra raw arguments appended after the standard flags.
    public let extraArgs: [String]

    public init(
        workspaceRoot: String,
        configuration: String? = "Debug",
        extraArgs: [String] = []
    ) {
        self.workspaceRoot = workspaceRoot
        self.configuration = configuration
        self.extraArgs = extraArgs
    }
}
