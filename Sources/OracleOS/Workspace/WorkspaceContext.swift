import Foundation

public struct WorkspaceContext: Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }
}
