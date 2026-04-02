import Foundation

/// Typed test specification. No generic shell execution.
public struct TestSpec: Sendable, Codable {
    public let workspaceRoot: String
    public let scheme: String?
    public let filter: String?
    public let failureOnly: Bool
    public let extraArgs: [String]

    public init(
        workspaceRoot: String,
        scheme: String? = nil,
        filter: String? = nil,
        failureOnly: Bool = false,
        extraArgs: [String] = []
    ) {
        self.workspaceRoot = workspaceRoot
        self.scheme = scheme
        self.filter = filter
        self.failureOnly = failureOnly
        self.extraArgs = extraArgs
    }
}
