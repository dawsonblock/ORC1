import Foundation

/// Validates postconditions after command execution.
/// Returns true if expected outcomes were achieved, false otherwise.
public struct PostconditionsValidator: Sendable {
    public init() {}
    
    public func validate(_ command: Command, outcome: ExecutionOutcome) throws -> Bool {
        // Check base execution status
        guard outcome.status != .failed else {
            throw PostconditionError.executionFailed
        }
        
        // For partial success, check if critical verifications passed
        if outcome.status == .partialSuccess {
            guard outcome.verifierReport.preconditionsPassed else {
                throw PostconditionError.preconditionsNotMet
            }
            guard outcome.verifierReport.policyDecision == "approved" else {
                throw PostconditionError.policyNotApproved
            }
        }
        
        // Validate verifier report is present and valid
        let report = outcome.verifierReport
        guard report.commandID == command.id else {
            throw PostconditionError.commandIDMismatch
        }
        
        // Verify preconditions were actually checked
        guard report.preconditionsPassed else {
            throw PostconditionError.preconditionsNotVerified
        }
        
        // Verify policy decision was made
        guard report.policyDecision == "approved" || report.policyDecision == "blocked" else {
            throw PostconditionError.invalidPolicyDecision(report.policyDecision)
        }
        
        // If policy was blocked, that's a failure
        if report.policyDecision == "blocked" {
            throw PostconditionError.policyBlocked(report.notes.joined(separator: ", "))
        }
        
        // Validate postconditions passed
        guard report.postconditionsPassed else {
            throw PostconditionError.postconditionsNotMet
        }
        
        // Validate observations were captured
        if outcome.observations.isEmpty && command.kind != "readElement" {
            // readElement may return empty observations, but others should have captured state
            // This is a warning rather than failure
            print("Warning: No observations captured for \(command.kind)")
        }
        
        return true
    }
}

/// Errors thrown by PostconditionsValidator
public enum PostconditionError: Error, CustomStringConvertible {
    case executionFailed
    case preconditionsNotMet
    case policyNotApproved
    case commandIDMismatch
    case preconditionsNotVerified
    case invalidPolicyDecision(String)
    case policyBlocked(String)
    case postconditionsNotMet
    case observationCaptureFailed
    
    public var description: String {
        switch self {
        case .executionFailed: return "Command execution failed"
        case .preconditionsNotMet: return "Preconditions were not met"
        case .policyNotApproved: return "Policy decision was not approved"
        case .commandIDMismatch: return "Command ID mismatch in verifier report"
        case .preconditionsNotVerified: return "Preconditions were not verified"
        case .invalidPolicyDecision(let decision): return "Invalid policy decision: \(decision)"
        case .policyBlocked(let reason): return "Policy blocked: \(reason)"
        case .postconditionsNotMet: return "Postconditions were not met"
        case .observationCaptureFailed: return "Failed to capture observations"
        }
    }
}
