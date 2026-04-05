// Types.swift - Shared types for Oracle OS v2
//
// Data structures used across modules. Keep these minimal and focused.

import AXorcist
import Foundation

// MARK: - Version

public enum OracleOS {
    public static let version = "2.0.6"
    public static let name = "oracle-os"
}

// MARK: - Tool Result

/// Standard result wrapper returned by all MCP tools.
public struct ToolResult: @unchecked Sendable {
    public let success: Bool
    public let data: [String: Any]?
    public let error: String?
    public let suggestion: String?
    public let context: ContextInfo?
    public let screenshotResult: ScreenshotResult?
    public let actionResult: ActionResult?
    public let traceResult: TraceResult?
    public let codeExecutionResult: CodeExecutionResult?
    public let recipeRunResult: RecipeRunResultPayload?

    public init(
        success: Bool,
        data: [String: Any]? = nil,
        error: String? = nil,
        suggestion: String? = nil,
        context: ContextInfo? = nil,
        screenshotResult: ScreenshotResult? = nil,
        actionResult: ActionResult? = nil,
        traceResult: TraceResult? = nil,
        codeExecutionResult: CodeExecutionResult? = nil,
        recipeRunResult: RecipeRunResultPayload? = nil
    ) {
        let resolvedScreenshotResult = screenshotResult ?? Self.extractScreenshotResult(from: data)
        let resolvedActionResult = actionResult ?? Self.extractActionResult(from: data)
        let resolvedTraceResult = traceResult ?? Self.extractTraceResult(from: data)
        let resolvedCodeExecutionResult = codeExecutionResult ?? Self.extractCodeExecutionResult(from: data)
        let resolvedRecipeRunResult = recipeRunResult ?? Self.extractRecipeRunResult(from: data)

        self.success = success
        self.data = Self.mergeData(
            data: data,
            screenshotResult: resolvedScreenshotResult,
            actionResult: resolvedActionResult,
            traceResult: resolvedTraceResult,
            codeExecutionResult: resolvedCodeExecutionResult,
            recipeRunResult: resolvedRecipeRunResult
        )
        self.error = error
        self.suggestion = suggestion
        self.context = context
        self.screenshotResult = resolvedScreenshotResult
        self.actionResult = resolvedActionResult
        self.traceResult = resolvedTraceResult
        self.codeExecutionResult = resolvedCodeExecutionResult
        self.recipeRunResult = resolvedRecipeRunResult
    }

    /// Convert to MCP-compatible dictionary for JSON serialization.
    public func toDict() -> [String: Any] {
        var result: [String: Any] = ["success": success]
        if let data { result["data"] = data }
        if let error { result["error"] = error }
        if let suggestion { result["suggestion"] = suggestion }
        if let context { result["context"] = context.toDict() }
        return result
    }
}

private extension ToolResult {
    static func extractScreenshotResult(from data: [String: Any]?) -> ScreenshotResult? {
        guard let data,
              let image = data["image"] as? String,
              let width = data["width"] as? Int,
              let height = data["height"] as? Int else {
            return nil
        }

        let windowFrame = data["window_frame"] as? [String: Any]
        return ScreenshotResult(
            base64PNG: image,
            width: width,
            height: height,
            windowTitle: data["window_title"] as? String,
            mimeType: data["mime_type"] as? String ?? "image/png",
            windowX: number(from: windowFrame?["x"]) ?? 0,
            windowY: number(from: windowFrame?["y"]) ?? 0,
            windowWidth: number(from: windowFrame?["width"]) ?? 0,
            windowHeight: number(from: windowFrame?["height"]) ?? 0
        )
    }

    static func extractActionResult(from data: [String: Any]?) -> ActionResult? {
        guard let dict = data?[ActionResultKey.actionResult] as? [String: Any] else {
            return nil
        }
        return ActionResult.from(dict: dict)
    }

    static func extractTraceResult(from data: [String: Any]?) -> TraceResult? {
        guard let dict = data?[ActionResultKey.trace] as? [String: Any] else {
            return nil
        }
        return TraceResult.from(dict: dict)
    }

    static func extractCodeExecutionResult(from data: [String: Any]?) -> CodeExecutionResult? {
        guard let dict = data?[ActionResultKey.codeExecution] as? [String: Any] else {
            return nil
        }
        return CodeExecutionResult.from(dict: dict)
    }

    static func extractRecipeRunResult(from data: [String: Any]?) -> RecipeRunResultPayload? {
        guard let data else {
            return nil
        }
        return RecipeRunResultPayload.from(data: data)
    }

    static func mergeData(
        data: [String: Any]?,
        screenshotResult: ScreenshotResult?,
        actionResult: ActionResult?,
        traceResult: TraceResult?,
        codeExecutionResult: CodeExecutionResult?,
        recipeRunResult: RecipeRunResultPayload?
    ) -> [String: Any]? {
        var merged = data ?? [:]

        if let screenshotResult {
            if merged["image"] == nil {
                merged["image"] = screenshotResult.base64PNG
            }
            if merged["width"] == nil {
                merged["width"] = screenshotResult.width
            }
            if merged["height"] == nil {
                merged["height"] = screenshotResult.height
            }
            if merged["window_title"] == nil, let windowTitle = screenshotResult.windowTitle {
                merged["window_title"] = windowTitle
            }
            if merged["mime_type"] == nil {
                merged["mime_type"] = screenshotResult.mimeType
            }
            if merged["window_frame"] == nil {
                merged["window_frame"] = [
                    "x": screenshotResult.windowX,
                    "y": screenshotResult.windowY,
                    "width": screenshotResult.windowWidth,
                    "height": screenshotResult.windowHeight,
                ]
            }
        }

        if let actionResult {
            merged[ActionResultKey.actionResult] = actionResult.toDict()
            if merged[ActionResultKey.method] == nil, let method = actionResult.method {
                merged[ActionResultKey.method] = method
            }
            if merged[ActionResultKey.approvalRequestID] == nil, let approvalRequestID = actionResult.approvalRequestID {
                merged[ActionResultKey.approvalRequestID] = approvalRequestID
            }
            if merged[ActionResultKey.approvalStatus] == nil, let approvalStatus = actionResult.approvalStatus {
                merged[ActionResultKey.approvalStatus] = approvalStatus
            }
        }

        if let traceResult {
            merged[ActionResultKey.trace] = traceResult.toDict()
        }

        if let codeExecutionResult {
            let codeExecutionData = codeExecutionResult.toDict()
            if !codeExecutionData.isEmpty {
                merged[ActionResultKey.codeExecution] = codeExecutionData
            }
        }

        if let recipeRunResult {
            merged.merge(recipeRunResult.toDict()) { _, new in new }
        }

        return merged.isEmpty ? nil : merged
    }

    static func number(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            return nil
        }
    }
}

// MARK: - Context Info

/// Lightweight context snapshot returned with tool results.
public struct ContextInfo: Sendable {
    public let app: String?
    public let window: String?
    public let focusedElement: String?
    public let url: String?

    public init(app: String? = nil, window: String? = nil, focusedElement: String? = nil, url: String? = nil) {
        self.app = app
        self.window = window
        self.focusedElement = focusedElement
        self.url = url
    }

    public func toDict() -> [String: Any] {
        var d: [String: Any] = [:]
        if let app { d["app"] = app }
        if let window { d["window"] = window }
        if let focusedElement { d["focused_element"] = focusedElement }
        if let url { d["url"] = url }
        return d
    }
}

// MARK: - Screenshot Result

/// Result from a screenshot capture.
public struct ScreenshotResult: Sendable {
    public let base64PNG: String
    public let width: Int
    public let height: Int
    public let windowTitle: String?
    public let mimeType: String

    /// Window frame in logical screen coordinates (points).
    /// Used by VisionScanner to map VLM coordinates back to screen space.
    public let windowX: Double
    public let windowY: Double
    public let windowWidth: Double
    public let windowHeight: Double

    public init(
        base64PNG: String,
        width: Int,
        height: Int,
        windowTitle: String? = nil,
        mimeType: String = "image/png",
        windowX: Double = 0,
        windowY: Double = 0,
        windowWidth: Double = 0,
        windowHeight: Double = 0
    ) {
        self.base64PNG = base64PNG
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.mimeType = mimeType
        self.windowX = windowX
        self.windowY = windowY
        self.windowWidth = windowWidth
        self.windowHeight = windowHeight
    }
}

// MARK: - Oracle Error

/// Errors specific to Oracle OS operations.
public enum OracleError: Error, Sendable {
    case timeout(seconds: TimeInterval)
    case elementNotFound(description: String)
    case actionFailed(description: String)
    case appNotFound(name: String)
    case permissionDenied(String)
    case invalidParameter(String)

    public var localizedDescription: String {
        switch self {
        case let .timeout(seconds):
            "Operation timed out after \(Int(seconds)) seconds"
        case let .elementNotFound(desc):
            "Element not found: \(desc)"
        case let .actionFailed(desc):
            "Action failed: \(desc)"
        case let .appNotFound(name):
            "Application not found: \(name)"
        case let .permissionDenied(msg):
            "Permission denied: \(msg)"
        case let .invalidParameter(msg):
            "Invalid parameter: \(msg)"
        }
    }
}

// MARK: - Constants

public enum OracleConstants {
    public static let semanticDepthBudget = 25
    public static let defaultTimeoutSeconds: TimeInterval = 30
    public static let defaultPollInterval: TimeInterval = 0.5
    public static let maxSearchDepth = 100
    public static var recipesDirectory: String { OracleProductPaths.recipesDirectory.path }
    public static var logsDirectory: String { OracleProductPaths.logsDirectory.path }
    public static var approvalsDirectory: String { OracleProductPaths.approvalsDirectory.path }
    public static var graphDirectory: String { OracleProductPaths.graphDirectory.path }
}
