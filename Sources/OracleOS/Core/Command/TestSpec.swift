import Foundation

/// Typed test specification. No generic shell execution.
/// Fields limited to what `swift test` actually consumes.
/// Xcode-only concepts (`scheme`, `failureOnly`) are not present.
public struct TestSpec: Sendable, Codable {
    public let workspaceRoot: String
    /// Passed as `--filter`. Nil runs all tests.
    public let filter: String?
    /// Extra raw arguments appended after the standard flags.
    public let extraArgs: [String]

    public init(
        workspaceRoot: String,
        filter: String? = nil,
        extraArgs: [String] = []
    ) {
        self.workspaceRoot = workspaceRoot
        self.filter = filter
        self.extraArgs = extraArgs
    }
}
