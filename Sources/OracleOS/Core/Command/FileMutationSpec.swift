import Foundation

/// Typed file mutation specification. Replaces generic shell write.
public struct FileMutationSpec: Sendable, Codable {
    public enum Operation: String, Sendable, Codable {
        case write
        case delete
        case append
    }

    public let path: String
    public let operation: Operation
    public let content: String?
    public let workspaceRoot: String?

    public init(
        path: String,
        operation: Operation,
        content: String? = nil,
        workspaceRoot: String? = nil
    ) {
        self.path = path
        self.operation = operation
        self.content = content
        self.workspaceRoot = workspaceRoot
    }
}
