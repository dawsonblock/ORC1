import Foundation

/// Typed build specification. No generic shell execution.
public struct BuildSpec: Sendable, Codable {
    public let workspaceRoot: String
    public let scheme: String?
    public let configuration: String?
    public let destination: String?
    public let extraArgs: [String]

    public init(
        workspaceRoot: String,
        scheme: String? = nil,
        configuration: String? = "Debug",
        destination: String? = nil,
        extraArgs: [String] = []
    ) {
        self.workspaceRoot = workspaceRoot
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
        self.extraArgs = extraArgs
    }
}
