// VisionSidecarContract.swift
// Typed contract for the Oracle OS ↔ vision-sidecar HTTP boundary.
//
// All data crossing this boundary must use these types. No free-form maps.
// Transport: HTTP to localhost:9876 (default). Port is runtime-configured.
// Breaking wire changes must update this file and vision-sidecar/schema/endpoints.py together.

import Foundation

// MARK: - Endpoint Paths

/// Canonical endpoint paths for the vision sidecar. Both the Swift runtime and
/// the Python sidecar must reference these constants — no inline string literals.
public enum VisionSidecarEndpoint {
    public static let health = "/health"
    public static let ground = "/ground"
    public static let detect = "/detect"
    public static let parse = "/parse"
}

// MARK: - Ground Request/Response

/// Request to `/ground` — find precise screen coordinates for a described element.
public struct VisionGroundRequest: Sendable, Codable {
    /// Base64-encoded PNG screenshot.
    public let image: String
    /// Natural language description of the target element.
    public let description: String
    /// Logical screen width in points. Default: 1728.
    public let screenW: Double
    /// Logical screen height in points. Default: 1117.
    public let screenH: Double
    /// Optional crop region [x1, y1, x2, y2] in logical points.
    /// When provided the sidecar runs VLM on the crop region and maps back.
    public let cropBox: [Double]?

    public init(
        image: String,
        description: String,
        screenW: Double = 1728,
        screenH: Double = 1117,
        cropBox: [Double]? = nil
    ) {
        self.image = image
        self.description = description
        self.screenW = screenW
        self.screenH = screenH
        self.cropBox = cropBox
    }

    public enum CodingKeys: String, CodingKey {
        case image, description
        case screenW = "screen_w"
        case screenH = "screen_h"
        case cropBox = "crop_box"
    }
}

/// Response from `/ground`.
public struct VisionGroundResponse: Sendable, Codable {
    /// X coordinate in logical screen points.
    public let x: Double
    /// Y coordinate in logical screen points.
    public let y: Double
    /// Normalised X in [0, 1].
    public let normalizedX: Double
    /// Normalised Y in [0, 1].
    public let normalizedY: Double
    /// Grounding confidence in [0, 1].
    public let confidence: Double?
    /// Raw model output text.
    public let raw: String?
    /// Inference time in milliseconds.
    public let inferenceMs: Int?
    /// Grounding method used: "full-screen" or "crop-based".
    public let method: String
    /// Echo of the crop box if crop-based grounding was used.
    public let cropBox: [Double]?
    /// Error message populated on failure (HTTP 4xx/5xx responses).
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case x, y, method, error, confidence, raw
        case normalizedX = "normalized_x"
        case normalizedY = "normalized_y"
        case inferenceMs = "inference_ms"
        case cropBox = "crop_box"
    }
}

// MARK: - Detect Request/Response

/// Request to `/detect` — detect all interactive UI elements on screen.
public struct VisionDetectRequest: Sendable, Codable {
    /// Base64-encoded PNG screenshot.
    public let image: String
    /// Logical screen width in points. Default: 1728.
    public let screenW: Double
    /// Logical screen height in points. Default: 1117.
    public let screenH: Double

    public init(image: String, screenW: Double = 1728, screenH: Double = 1117) {
        self.image = image
        self.screenW = screenW
        self.screenH = screenH
    }

    public enum CodingKeys: String, CodingKey {
        case image
        case screenW = "screen_w"
        case screenH = "screen_h"
    }
}

/// Response from `/detect`.
public struct VisionDetectResponse: Sendable, Codable {
    public let status: String
    /// Detected elements in the order returned by the detector.
    public let elements: [VisionSidecarElement]
    public let count: Int
    public let suggestion: String?
    public let error: String?
}

/// Canonical sidecar element shape shared by `/detect` and `/parse`.
public struct VisionSidecarElement: Sendable, Codable, Equatable {
    public let id: String
    public let type: String
    public let confidence: Double
    public let box: [Double]
    public let text: String?
    public let source: String

    public init(
        id: String,
        type: String,
        confidence: Double,
        box: [Double],
        text: String? = nil,
        source: String
    ) {
        self.id = id
        self.type = type
        self.confidence = confidence
        self.box = box
        self.text = text
        self.source = source
    }

    public var frame: VisionFrame? {
        guard box.count == 4 else { return nil }
        return VisionFrame(x: box[0], y: box[1], width: box[2], height: box[3])
    }
}

// MARK: - Parse Request/Response

/// Request to `/parse` — structured element map of the full screen.
public struct VisionParseRequest: Sendable, Codable {
    /// Base64-encoded PNG screenshot.
    public let image: String
    /// Logical screen width in points. Default: 1728.
    public let screenW: Double
    /// Logical screen height in points. Default: 1117.
    public let screenH: Double

    public init(image: String, screenW: Double = 1728, screenH: Double = 1117) {
        self.image = image
        self.screenW = screenW
        self.screenH = screenH
    }

    public enum CodingKeys: String, CodingKey {
        case image
        case screenW = "screen_w"
        case screenH = "screen_h"
    }
}

/// Response from `/parse`. Shape is determined by ScreenParser and may evolve;
/// typed fields cover the stable surface, extras are in `extra`.
public struct VisionParseResponse: Sendable, Codable {
    public let status: String?
    public let elements: [VisionSidecarElement]?
    public let count: Int?
    public let context: String?
    public let error: String?
}

// MARK: - Health Response

/// Response from `GET /health`.
public struct VisionHealthResponse: Sendable, Codable {
    /// "ready" when the VLM model is loaded, "idle" otherwise.
    public let status: String
    public let version: String
    public let modelsLoaded: [String]
    public let modelPath: String
    public let modelExists: Bool
    public let vlmLoadError: String?
    public let idleTimeout: Int
    public let pid: Int

    public enum CodingKeys: String, CodingKey {
        case status, version, pid
        case modelsLoaded = "models_loaded"
        case modelPath = "model_path"
        case modelExists = "model_exists"
        case vlmLoadError = "vlm_load_error"
        case idleTimeout = "idle_timeout"
    }

    /// Convenience: returns true when the sidecar has a VLM model loaded and ready.
    public var isReady: Bool { status == "ready" }
}

protocol VisionSidecarErrorCarrier {
    var error: String? { get }
}

extension VisionGroundResponse: VisionSidecarErrorCarrier {}
extension VisionDetectResponse: VisionSidecarErrorCarrier {}
extension VisionParseResponse: VisionSidecarErrorCarrier {}
