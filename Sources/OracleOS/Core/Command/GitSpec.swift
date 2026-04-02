import Foundation

/// Typed git operation specification. No generic shell execution.
public struct GitSpec: Sendable, Codable {
    public enum Operation: String, Sendable, Codable {
        case status
        case diff
        case commit
        case branch
        case checkout
        case add
        case push
        case pull
        case merge
        case rebase
    }

    public let operation: Operation
    public let args: [String]  // operation-specific arguments
    public let workspaceRoot: String

    public init(
        operation: Operation,
        args: [String] = [],
        workspaceRoot: String
    ) {
        self.operation = operation
        self.args = args
        self.workspaceRoot = workspaceRoot
    }
}
