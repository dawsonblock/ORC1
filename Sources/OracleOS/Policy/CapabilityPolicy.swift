import Foundation
public struct CapabilityPolicy: Sendable {
    public let allowedCapabilities: Set<String>
    public init(allowedCapabilities: Set<String> = []) { self.allowedCapabilities = allowedCapabilities }
}
