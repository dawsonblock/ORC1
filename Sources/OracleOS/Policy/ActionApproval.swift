import Foundation
public struct ActionApproval: Sendable {
    public let approved: Bool; public let conditions: [String]
    public init(approved: Bool, conditions: [String] = []) { self.approved = approved; self.conditions = conditions }
}
