// VisionContract.swift
// v1 typed contract for the vision-sidecar boundary.
//
// All data crossing the runtime ↔ vision-sidecar boundary must use these types.
// No free-form maps. No internal runtime types exposed here.
// Version field is mandatory. Add new versions instead of mutating v1 fields.
//
// Transport: HTTP POST to sidecar endpoint (path /v1/detect).
// Failure: always returns VisionResponse with a populated error field.

import Foundation

// MARK: - Vision Request

/// A typed, Sendable request to the vision-sidecar.
/// Covers all current vision operations: detect, classify, OCR.
public struct VisionRequest: Sendable, Codable {
    /// Wire version. Current supported value: "1".
    public let version: String

    /// What to do with the image.
    public let operation: VisionOperation

    /// Image input — exactly one field must be populated.
    public let image: VisionImageInput

    /// Optional tuning parameters.
    public let parameters: VisionParameters?

    public init(
        version: String = "1",
        operation: VisionOperation,
        image: VisionImageInput,
        parameters: VisionParameters? = nil
    ) {
        self.version = version
        self.operation = operation
        self.image = image
        self.parameters = parameters
    }
}

// MARK: - Vision Operation

/// The operation the sidecar should perform on the image.
public enum VisionOperation: String, Sendable, Codable {
    /// Detect objects, UI elements, or regions of interest.
    case detect
    /// Classify the primary subject of the image.
    case classify
    /// Extract text (OCR).
    case ocr
    /// Detect and classify UI interaction elements.
    case uiElements
}

// MARK: - Vision Image Input

/// Exactly one field must be non-nil. The sidecar rejects requests where
/// zero or more than one field is populated.
public struct VisionImageInput: Sendable, Codable {
    /// Absolute path to a local image file. Sidecar must have read access.
    public let filePath: String?
    /// Raw image bytes, base64-encoded.
    public let base64Bytes: String?
    /// Opaque artifact ID referencing an image stored by the runtime.
    public let artifactID: String?

    public init(filePath: String? = nil, base64Bytes: String? = nil, artifactID: String? = nil) {
        self.filePath = filePath
        self.base64Bytes = base64Bytes
        self.artifactID = artifactID
    }

    /// Returns true if exactly one field is populated.
    public var isValid: Bool {
        let populated = [filePath, base64Bytes, artifactID].compactMap { $0 }.count
        return populated == 1
    }
}

// MARK: - Vision Parameters

/// Optional tuning parameters. All fields are optional with sensible defaults.
public struct VisionParameters: Sendable, Codable {
    /// Minimum confidence threshold (0.0–1.0). Results below this are dropped.
    public let confidenceThreshold: Double?
    /// Model hint for the sidecar to prefer a specific model variant.
    public let modelHint: String?
    /// Maximum number of results to return.
    public let maxResults: Int?

    public init(
        confidenceThreshold: Double? = nil,
        modelHint: String? = nil,
        maxResults: Int? = nil
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.modelHint = modelHint
        self.maxResults = maxResults
    }
}

// MARK: - Vision Response

/// Typed response from the vision-sidecar.
/// On failure, results is empty and error is populated.
public struct VisionResponse: Sendable, Codable {
    /// Wire version. Always "1".
    public let version: String
    /// Ordered list of detection/classification/OCR results.
    public let results: [VisionResult]
    /// Populated on failure.
    public let error: VisionError?

    public init(version: String = "1", results: [VisionResult], error: VisionError? = nil) {
        self.version = version
        self.results = results
        self.error = error
    }

    public var succeeded: Bool { error == nil }
}

// MARK: - Vision Result

/// A single result item from the sidecar.
public struct VisionResult: Sendable, Codable {
    /// Human-readable label for the detected item.
    public let label: String
    /// Confidence score (0.0–1.0).
    public let confidence: Double
    /// Bounding box in image-relative coordinates (0.0–1.0), if applicable.
    public let boundingBox: VisionRect?
    /// Structured metadata (e.g. OCR text, element role).
    public let metadata: [String: String]

    public init(
        label: String,
        confidence: Double,
        boundingBox: VisionRect? = nil,
        metadata: [String: String] = [:]
    ) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.metadata = metadata
    }
}

// MARK: - Vision Rect

/// Normalised bounding rectangle (values in 0.0–1.0 range).
public struct VisionRect: Sendable, Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Vision Error

/// Structured error from the vision-sidecar.
/// Every failure maps to a stable code — never a raw string.
public struct VisionError: Sendable, Codable, Error {
    public let code: VisionErrorCode
    /// Human-readable detail for logging. Not machine-parsed.
    public let detail: String

    public init(code: VisionErrorCode, detail: String) {
        self.code = code
        self.detail = detail
    }
}

/// Stable error codes for the vision-sidecar contract.
public enum VisionErrorCode: String, Sendable, Codable {
    case timeout
    case modelUnavailable
    case invalidInput
    case partialResult
    case unsupportedVersion
    case internalError
}
