import Foundation

/// Validates preconditions before command execution.
/// Returns false if required conditions are not met.
public struct PreconditionsValidator: Sendable {
    public init() {}
    
    public func validate(_ command: Command, state: WorldModelSnapshot) throws -> Bool {
        // Validate based on command domain
        switch command.kind {
        // UI Commands require active application context
        // Supports both canonical ("click", "type") and legacy ("clickElement", "typeText") forms
        case "click", "clickElement", "type", "typeText", "focus", "focusWindow", "read", "readElement":
            guard state.activeApplication != nil else {
                throw PreconditionError.noActiveApplication
            }
            guard !state.modalPresent else {
                throw PreconditionError.modalPresent
            }
            
        // Code Commands require repository context
        // Supports both canonical ("build", "test") and legacy ("runBuild", "runTests") forms
        case "search", "searchRepository", "search_code", "read_repository",
             "modify", "file", "open_file",
             "build", "runBuild", "test", "runTests", "readFile":
            guard state.repositoryRoot != nil else {
                throw PreconditionError.noRepositoryContext
            }
            // Block dangerous operations on dirty git state
            if (command.kind == "modify" || command.kind == "file") && state.isGitDirty {
                throw PreconditionError.gitDirty
            }
            
        // System Commands require no modal
        case "launch", "launchApp", "open", "openURL":
            guard !state.modalPresent else {
                throw PreconditionError.modalPresent
            }
            
        default:
            // Unknown command kind - fail safe
            throw PreconditionError.unknownCommand(command.kind)
        }
        
        // Validate metadata has required intent ID
        let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard command.metadata.intentID != zeroUUID else {
            throw PreconditionError.invalidIntentID
        }
        
        // Validate confidence threshold
        guard command.metadata.confidence >= 0.5 else {
            throw PreconditionError.lowConfidence(command.metadata.confidence)
        }
        
        return true
    }
}

/// Errors thrown by PreconditionsValidator
public enum PreconditionError: Error, CustomStringConvertible {
    case noActiveApplication
    case modalPresent
    case noRepositoryContext
    case gitDirty
    case unknownCommand(String)
    case invalidIntentID
    case lowConfidence(Double)
    
    public var description: String {
        switch self {
        case .noActiveApplication: return "No active application context"
        case .modalPresent: return "Modal dialog present - cannot execute"
        case .noRepositoryContext: return "No repository context for code command"
        case .gitDirty: return "Git working directory is dirty"
        case .unknownCommand(let kind): return "Unknown command kind: \(kind)"
        case .invalidIntentID: return "Invalid or missing intent ID in metadata"
        case .lowConfidence(let confidence): return "Confidence \(confidence) below threshold 0.5"
        }
    }
}
