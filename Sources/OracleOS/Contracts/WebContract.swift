// WebContract.swift
// v1 typed contract for the web interface boundary.
//
// The web layer is event-driven. It does NOT call internal services directly.
// It may only:
//   1. Submit intents (command intake)
//   2. Subscribe to events (event output stream)
//   3. Fetch artifacts by ID (artifact retrieval)
//
// Version field is mandatory on every message.
// Event types are versioned (e.g. "run.started.v1") — never mutated.
// Unknown versions are rejected at intake with an explicit error.

import Foundation

// MARK: - Command Intake

/// A typed intent submission from the web layer.
/// The web layer does not submit commands directly — it submits intents.
/// The runtime decides how to plan and execute.
public struct WebIntentSubmission: Sendable, Codable {
    /// Wire version. Current supported value: "1".
    public let version: String
    /// Client-generated correlation ID for tracking this submission.
    public let clientID: String
    /// The intent to submit.
    public let intent: WebIntent
    /// Optional context hints (e.g. active app, workspace root).
    public let context: WebSubmissionContext?

    public init(
        version: String = "1",
        clientID: String,
        intent: WebIntent,
        context: WebSubmissionContext? = nil
    ) {
        self.version = version
        self.clientID = clientID
        self.intent = intent
        self.context = context
    }
}

/// The intent payload carried by a WebIntentSubmission.
public struct WebIntent: Sendable, Codable {
    /// Human-readable objective (e.g. "Run all tests").
    public let objective: String
    /// Domain hint: "ui" or "code".
    public let domain: String
    /// Additional key-value metadata. Values must be JSON-safe strings.
    public let metadata: [String: String]

    public init(objective: String, domain: String, metadata: [String: String] = [:]) {
        self.objective = objective
        self.domain = domain
        self.metadata = metadata
    }
}

/// Optional context accompanying a web intent submission.
public struct WebSubmissionContext: Sendable, Codable {
    public let workspaceRoot: String?
    public let activeApp: String?

    public init(workspaceRoot: String? = nil, activeApp: String? = nil) {
        self.workspaceRoot = workspaceRoot
        self.activeApp = activeApp
    }
}

/// Immediate acknowledgement returned for a WebIntentSubmission.
public struct WebSubmissionAck: Sendable, Codable {
    /// Wire version. Always "1".
    public let version: String
    /// Mirrors the clientID from the submission.
    public let clientID: String
    /// Runtime-assigned intent ID for tracking.
    public let intentID: String
    /// Always "accepted" or an error code.
    public let status: String
    /// Populated when status is not "accepted".
    public let error: WebError?

    public init(
        version: String = "1",
        clientID: String,
        intentID: String,
        status: String,
        error: WebError? = nil
    ) {
        self.version = version
        self.clientID = clientID
        self.intentID = intentID
        self.status = status
        self.error = error
    }
}

// MARK: - Event Output Stream

/// A versioned event emitted on the web event stream.
/// Event type names are stable versioned strings (e.g. "run.started.v1").
/// New event shapes get a new version suffix — existing shapes are never mutated.
public struct WebEvent: Sendable, Codable {
    /// Wire version. Always "1".
    public let version: String
    /// Stable versioned event type identifier (e.g. "run.started.v1").
    public let type: String
    /// Correlation ID linking this event to an intent submission.
    public let correlationID: String
    /// ISO-8601 timestamp.
    public let timestamp: String
    /// Event payload. Schema depends on `type`. Closed per event type below.
    public let payload: JSONValue

    public init(
        version: String = "1",
        type: String,
        correlationID: String,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        payload: JSONValue
    ) {
        self.version = version
        self.type = type
        self.correlationID = correlationID
        self.timestamp = timestamp
        self.payload = payload
    }
}

/// Known stable event type identifiers for the v1 web stream.
public enum WebEventType {
    public static let runStartedV1 = "run.started.v1"
    public static let runCompletedV1 = "run.completed.v1"
    public static let runFailedV1 = "run.failed.v1"
    public static let stepCompletedV1 = "step.completed.v1"
    public static let stepFailedV1 = "step.failed.v1"
    public static let artifactAvailableV1 = "artifact.available.v1"
    public static let policyBlockedV1 = "policy.blocked.v1"
    public static let approvalRequiredV1 = "approval.required.v1"
}

// MARK: - Artifact Retrieval

/// A request to fetch an artifact by ID.
/// The runtime owns storage. The web layer requests by ID — never by path.
public struct ArtifactFetchRequest: Sendable, Codable {
    /// Wire version. Current supported value: "1".
    public let version: String
    /// Opaque artifact ID assigned by the runtime.
    public let artifactID: String
    /// Expected artifact kind (used for validation, not routing).
    public let kind: ArtifactKind

    public init(version: String = "1", artifactID: String, kind: ArtifactKind) {
        self.version = version
        self.artifactID = artifactID
        self.kind = kind
    }
}

/// The kind of artifact being requested.
public enum ArtifactKind: String, Sendable, Codable {
    case log
    case patch
    case diagnostic
    case file
    case screenshot
    case trace
}

/// Response to an artifact fetch request.
public struct ArtifactFetchResponse: Sendable, Codable {
    /// Wire version. Always "1".
    public let version: String
    /// The artifact ID from the request.
    public let artifactID: String
    /// The artifact kind.
    public let kind: ArtifactKind
    /// Base64-encoded artifact contents.
    public let base64Contents: String?
    /// MIME type of the artifact.
    public let mimeType: String?
    /// Populated on failure.
    public let error: WebError?

    public init(
        version: String = "1",
        artifactID: String,
        kind: ArtifactKind,
        base64Contents: String? = nil,
        mimeType: String? = nil,
        error: WebError? = nil
    ) {
        self.version = version
        self.artifactID = artifactID
        self.kind = kind
        self.base64Contents = base64Contents
        self.mimeType = mimeType
        self.error = error
    }

    public var succeeded: Bool { error == nil }
}

// MARK: - Web Error

/// Structured error for all web contract failures.
public struct WebError: Sendable, Codable, Error {
    public let code: WebErrorCode
    /// Human-readable detail for logging. Not machine-parsed.
    public let detail: String

    public init(code: WebErrorCode, detail: String) {
        self.code = code
        self.detail = detail
    }
}

/// Stable error codes for the web contract.
public enum WebErrorCode: String, Sendable, Codable {
    case unsupportedVersion
    case invalidPayload
    case intentRejected
    case artifactNotFound
    case timeout
    case internalError
}
