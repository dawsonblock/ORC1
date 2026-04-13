// VisionScanner.swift - Vision-based perception tools for Oracle OS
//
// Maps to MCP tools: oracle_parse_screen, oracle_ground
//
// These tools use the Python vision sidecar (localhost:9876) for ML inference.
// The sidecar provides best-effort grounding and experimental full-screen parsing.
//
// Architecture:
//   oracle_parse_screen → screenshot → sidecar /parse → experimental structured output
//   oracle_ground       → screenshot → sidecar /ground → (x, y) coordinates
//
// Both tools take a screenshot automatically using the existing ScreenCapture
// module, then send it to the sidecar for processing.

import AppKit
import Foundation

/// ⚠️ EXPERIMENTAL — Vision-based perception tools.
///
/// These tools use the Python vision sidecar and are NOT part of the
/// supported commit-authority path. The supported runtime remains functional
/// without them.
///
/// Allowed usage:
/// - Debugging and offline evaluation
/// - Optional enrichment when sidecar is available
/// - Fallback when AX tree is insufficient
///
/// Prohibited usage:
/// - Supported planners MUST NOT depend on vision output for decision-making
/// - The supported runtime loop MUST NOT block on sidecar availability
@MainActor
public enum VisionScanner {
    static let minimumReportedGroundConfidence = 0.3
    static let minimumActionableGroundConfidence = 0.5

    struct GroundingContext: Equatable {
        let sidecarWidth: Double
        let sidecarHeight: Double
        let offsetX: Double
        let offsetY: Double
        let isEffectivelyFullscreen: Bool

        func mapToScreen(x: Double, y: Double) -> (x: Double, y: Double) {
            (x + offsetX, y + offsetY)
        }
    }

    // MARK: - oracle_parse_screen

    /// Experimental full-screen vision parsing.
    /// The sidecar can return structured output, but the runtime still treats
    /// this as a best-effort experimental perception surface.
    public static func parseScreen(
        appName: String?,
        fullResolution: Bool
    ) -> ToolResult {
        // Check sidecar availability
        guard VisionBridge.isAvailable() else {
            return sidecarUnavailableResult(tool: "oracle_parse_screen")
        }

        // Take screenshot
        guard let screenshot = captureForVision(appName: appName, fullResolution: fullResolution)
        else {
            return ToolResult(
                success: false,
                error: "Screenshot capture failed",
                suggestion: "Ensure Screen Recording permission is granted"
            )
        }

        // Get main display dimensions for mapping
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let displayWidth = Double(mainScreen?.frame.width ?? 1728)
        let displayHeight = Double(mainScreen?.frame.height ?? 1117)

        // Call VLM parsing
        guard
            let response = VisionBridge.parse(
                imageBase64: screenshot.base64PNG,
                screenWidth: displayWidth,
                screenHeight: displayHeight
            )
        else {
            return ToolResult(
                success: false,
                error: "Vision parsing failed",
                suggestion: "The vision sidecar may have crashed. Check its logs."
            )
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let encodedResponse = encodeJSONObject(response) ?? [:]
        switch parsePerceptionFrame(
            from: response,
            screenWidth: displayWidth,
            screenHeight: displayHeight,
            timestamp: timestamp
        ) {
        case .success:
            return ToolResult(
                success: true,
                data: encodedResponse,
                suggestion: response.context ?? "Screen parsed successfully via vision sidecar."
            )
        case .failure(let violations):
            var failureData = encodedResponse
            failureData["validator_violations"] = violations
            return ToolResult(
                success: false,
                data: failureData,
                error: "Vision parse response failed contract validation",
                suggestion: violations.joined(separator: " | ")
            )
        }
    }

    // MARK: - oracle_ground

    /// Find precise screen coordinates for a described UI element using VLM.
    /// Takes a screenshot, sends it to the vision sidecar with the description,
    /// and returns the (x, y) coordinates where the element was found.
    public static func groundElement(
        description: String,
        appName: String?,
        cropBox: [Double]?
    ) -> ToolResult {
        if let cropBoxError = validateCropBox(cropBox) {
            return ToolResult(
                success: false,
                error: cropBoxError,
                suggestion:
                    "Pass crop_box as [x1, y1, x2, y2] in logical screen points with x2>x1 and y2>y1."
            )
        }

        // Check sidecar availability, try to start it if not running
        if !VisionBridge.isAvailable() {
            Log.info("Vision sidecar not running, attempting to start...")
            if !VisionBridge.startSidecar() {
                return sidecarUnavailableResult(tool: "oracle_ground")
            }
        }

        // Take screenshot (1280px width is ideal for VLM)
        guard let screenshot = captureForVision(appName: appName, fullResolution: false) else {
            return ToolResult(
                success: false,
                error: "Screenshot capture failed",
                suggestion: "Ensure Screen Recording permission is granted"
            )
        }

        // ── Coordinate mapping strategy ──
        //
        // Problem: SCK's desktopIndependentWindow captures the FULL Chrome window
        // (tabs, address bar, web content) but reports the frame of only the
        // content sub-window. The relationship between SCK frame and actual
        // captured area is unreliable for Chrome/Electron apps.
        //
        // Solution: Pass the MAIN DISPLAY logical dimensions as screen_w/screen_h.
        // For a maximized/fullscreen app, the screenshot covers essentially the
        // full display. The VLM normalizes coordinates to [0,1] relative to the
        // image, and multiplying by display dimensions gives screen-absolute
        // coordinates directly — no offset needed.
        //
        // This works because:
        // 1. Chrome in fullscreen covers the entire display
        // 2. VLM sees the screenshot as covering the full display area
        // 3. Normalized coords * display size = screen absolute coords
        //
        // For non-fullscreen windows, we fall back to window-relative mapping.

        let screenshotWidth = Double(screenshot.width)
        let screenshotHeight = Double(screenshot.height)
        let windowWidth = screenshot.windowWidth
        let windowHeight = screenshot.windowHeight
        let windowX = screenshot.windowX
        let windowY = screenshot.windowY

        // Get main display dimensions for fullscreen mapping
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let displayWidth = Double(mainScreen?.frame.width ?? 1728)
        let displayHeight = Double(mainScreen?.frame.height ?? 1117)
        let mappingContext = groundingContext(
            screenshotWidth: screenshotWidth,
            screenshotHeight: screenshotHeight,
            windowWidth: windowWidth,
            windowHeight: windowHeight,
            windowX: windowX,
            windowY: windowY,
            displayWidth: displayWidth,
            displayHeight: displayHeight
        )

        // Call VLM grounding
        guard
            let result = VisionBridge.ground(
                imageBase64: screenshot.base64PNG,
                description: description,
                screenWidth: mappingContext.sidecarWidth,
                screenHeight: mappingContext.sidecarHeight,
                cropBox: cropBox
            )
        else {
            return ToolResult(
                success: false,
                error: "VLM grounding failed for '\(description)'",
                suggestion: "The vision sidecar may have crashed. Check its logs or restart it."
            )
        }

        // Map to screen-absolute coordinates
        let mappedPoint = mappingContext.mapToScreen(x: result.x, y: result.y)
        let mappedX = mappedPoint.x
        let mappedY = mappedPoint.y
        Log.info(
            "Vision ground: sidecar(\(Int(mappingContext.sidecarWidth))x\(Int(mappingContext.sidecarHeight))) → VLM (\(Int(result.x)),\(Int(result.y))) + offset (\(Int(mappingContext.offsetX)),\(Int(mappingContext.offsetY))) → screen (\(Int(mappedX)),\(Int(mappedY))) [fullscreen=\(mappingContext.isEffectivelyFullscreen)]"
        )

        // Build response with screen-logical coordinates
        var data: [String: Any] = [
            "x": mappedX,
            "y": mappedY,
            "confidence": result.confidence,
            "method": result.method,
            "description": description,
            "inference_ms": result.inferenceMs,
            "screen_size": ["width": Int(screenshotWidth), "height": Int(screenshotHeight)],
            "window_frame": [
                "x": Int(windowX), "y": Int(windowY),
                "width": Int(windowWidth), "height": Int(windowHeight),
            ],
            "display_size": ["width": Int(displayWidth), "height": Int(displayHeight)],
            "vlm_raw": ["x": result.x, "y": result.y],
        ]

        if let cropBox, cropBox.count == 4 {
            data["crop_box"] = cropBox
        }

        // Include suggestion based on confidence
        var suggestion: String?
        if result.confidence < minimumReportedGroundConfidence {
            suggestion =
                "Low confidence (\(result.confidence)). The element may not be visible on screen. "
                + "Try oracle_screenshot to verify, or use oracle_find for AX-based search."
        } else if result.confidence < 0.6 {
            suggestion =
                "Medium confidence. Consider using crop_box to narrow the search area for better accuracy."
        }

        return ToolResult(
            success: result.confidence >= minimumReportedGroundConfidence,
            data: data,
            error: result.confidence >= minimumReportedGroundConfidence
                ? nil
                : "Low-confidence VLM grounding for '\(description)'",
            suggestion: suggestion
        )
    }

    // MARK: - Vision-Enhanced Find (fallback for oracle_find)

    /// Try to find an element using VLM grounding as a fallback when AX search fails.
    /// Called by AXScanner.findElements when AX returns no results.
    ///
    /// Returns a synthetic element summary with VLM-grounded coordinates that can
    /// be used directly with oracle_click(x:, y:).
    public static func visionFallbackFind(
        query: String,
        appName: String?
    ) -> [[String: Any]]? {
        // Only try if sidecar is available (don't block on startup)
        guard VisionBridge.isAvailable() else {
            return nil
        }

        // Take screenshot
        guard let screenshot = captureForVision(appName: appName, fullResolution: false) else {
            return nil
        }

        // Use display dimensions for fullscreen apps, window dims otherwise
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let displayW = Double(mainScreen?.frame.width ?? 1728)
        let displayH = Double(mainScreen?.frame.height ?? 1117)
        let mappingContext = groundingContext(
            screenshotWidth: Double(screenshot.width),
            screenshotHeight: Double(screenshot.height),
            windowWidth: screenshot.windowWidth,
            windowHeight: screenshot.windowHeight,
            windowX: screenshot.windowX,
            windowY: screenshot.windowY,
            displayWidth: displayW,
            displayHeight: displayH
        )

        // Run VLM grounding
        guard
            let result = VisionBridge.ground(
                imageBase64: screenshot.base64PNG,
                description: query,
                screenWidth: mappingContext.sidecarWidth,
                screenHeight: mappingContext.sidecarHeight
            )
        else {
            return nil
        }

        // Only return if confidence is reasonable
        guard result.confidence >= minimumActionableGroundConfidence else {
            Log.info(
                "Vision fallback for '\(query)': low confidence \(result.confidence), skipping")
            return nil
        }

        let mappedPoint = mappingContext.mapToScreen(x: result.x, y: result.y)
        let mappedX = Int(mappedPoint.x)
        let mappedY = Int(mappedPoint.y)

        Log.info(
            "Vision fallback found '\(query)' at screen (\(mappedX), \(mappedY)) conf=\(result.confidence)"
        )

        // Return as a synthetic element summary matching oracle_find's output format
        let element: [String: Any] = [
            "name": query,
            "role": "VisionGrounded",
            "position": ["x": mappedX, "y": mappedY],
            "size": ["width": 40, "height": 40],  // Approximate click target
            "actionable": true,
            "grounded_by": "vlm",
            "confidence": result.confidence,
            "note":
                "Found by VLM vision grounding. Use oracle_click with x:\(mappedX) y:\(mappedY) to click.",
        ]

        return [element]
    }

    // MARK: - Vision-Enhanced Click (fallback for oracle_click)

    /// Try to click an element using VLM grounding as a fallback when AX can't find it.
    /// Called by Actions.click when AX-based click fails.
    ///
    /// Takes a screenshot, runs VLM grounding to find the element, then clicks
    /// at the grounded coordinates.
    public static func visionFallbackClick(
        query: String,
        appName: String?
    ) -> ToolResult? {
        // Only try if sidecar is available
        guard VisionBridge.isAvailable() else {
            return nil
        }

        // Take screenshot
        guard let screenshot = captureForVision(appName: appName, fullResolution: false) else {
            return nil
        }

        // Use display dimensions for fullscreen apps, window dims otherwise
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let displayW = Double(mainScreen?.frame.width ?? 1728)
        let displayH = Double(mainScreen?.frame.height ?? 1117)
        let mappingContext = groundingContext(
            screenshotWidth: Double(screenshot.width),
            screenshotHeight: Double(screenshot.height),
            windowWidth: screenshot.windowWidth,
            windowHeight: screenshot.windowHeight,
            windowX: screenshot.windowX,
            windowY: screenshot.windowY,
            displayWidth: displayW,
            displayHeight: displayH
        )

        // Run VLM grounding
        guard
            let result = VisionBridge.ground(
                imageBase64: screenshot.base64PNG,
                description: query,
                screenWidth: mappingContext.sidecarWidth,
                screenHeight: mappingContext.sidecarHeight
            )
        else {
            return nil
        }

        // Only click if confidence is reasonable
        guard result.confidence >= minimumActionableGroundConfidence else {
            Log.info("Vision click fallback for '\(query)': low confidence \(result.confidence)")
            return nil
        }

        let mappedPoint = mappingContext.mapToScreen(x: result.x, y: result.y)
        let mappedX = mappedPoint.x
        let mappedY = mappedPoint.y

        Log.info(
            "Vision click: '\(query)' at screen (\(Int(mappedX)), \(Int(mappedY))) conf=\(result.confidence)"
        )

        return ToolResult(
            success: true,
            data: [
                "x": mappedX,
                "y": mappedY,
                "confidence": result.confidence,
                "method": "vlm-grounded",
                "description": query,
                "inference_ms": result.inferenceMs,
                "note":
                    "Element found by VLM vision grounding. Use oracle_click(x:\(Int(mappedX)), y:\(Int(mappedY))) to click.",
            ],
            suggestion:
                "To click this element, use oracle_click with x:\(Int(mappedX)) y:\(Int(mappedY))"
        )
    }

    // MARK: - Private Helpers

    /// Capture a screenshot suitable for vision processing.
    /// Uses the existing ScreenCapture module (same as oracle_screenshot).
    /// Includes activate-and-retry logic for windows that are off-screen.
    private static func captureForVision(
        appName: String?,
        fullResolution: Bool
    ) -> ScreenshotResult? {
        let targetApp: NSRunningApplication
        if let appName {
            guard let app = AXScanner.findApp(named: appName) else {
                return nil
            }
            targetApp = app
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            targetApp = frontApp
        }

        let pid = targetApp.processIdentifier

        // First attempt: capture without focus change.
        let (firstResult, firstFailure) = ScreenCapture.captureWindowSyncWithReason(
            pid: pid, fullResolution: fullResolution
        )
        if let firstResult {
            return firstResult
        }

        // If the failure is fixable by activating the app, try that.
        switch firstFailure {
        case .noPermission, .windowListUnavailable:
            // Cannot fix by activating.
            return nil
        case .noWindowsForApp, .captureReturnedNil, .imageTooSmall, nil:
            break
        }

        // Retry: activate the app to bring windows on-screen.
        Log.info("VisionCapture: retrying after focus for \(targetApp.localizedName ?? "app")")
        targetApp.activate()
        Thread.sleep(forTimeInterval: 0.5)

        let (retryResult, _) = ScreenCapture.captureWindowSyncWithReason(
            pid: pid, fullResolution: fullResolution
        )
        return retryResult
    }

    /// Standard error result when the vision sidecar is not available.
    private static func sidecarUnavailableResult(tool: String) -> ToolResult {
        ToolResult(
            success: false,
            error: "Vision sidecar not running. \(tool) requires the Python vision sidecar.",
            suggestion: "Start the sidecar: cd vision-sidecar && python3 server.py &\n"
                + "Or use oracle_find for AX-based element search (works without sidecar)."
        )
    }

    static func groundingContext(
        screenshotWidth: Double,
        screenshotHeight: Double,
        windowWidth: Double,
        windowHeight: Double,
        windowX: Double,
        windowY: Double,
        displayWidth: Double,
        displayHeight: Double
    ) -> GroundingContext {
        let isEffectivelyFullscreen = windowWidth > 0 && (windowWidth / displayWidth) > 0.9
        if isEffectivelyFullscreen {
            return GroundingContext(
                sidecarWidth: displayWidth,
                sidecarHeight: displayHeight,
                offsetX: 0,
                offsetY: 0,
                isEffectivelyFullscreen: true
            )
        }

        if windowWidth > 0 && windowHeight > 0 {
            return GroundingContext(
                sidecarWidth: windowWidth,
                sidecarHeight: windowHeight,
                offsetX: windowX,
                offsetY: windowY,
                isEffectivelyFullscreen: false
            )
        }

        return GroundingContext(
            sidecarWidth: screenshotWidth,
            sidecarHeight: screenshotHeight,
            offsetX: 0,
            offsetY: 0,
            isEffectivelyFullscreen: false
        )
    }

    static func validateCropBox(_ cropBox: [Double]?) -> String? {
        guard let cropBox else { return nil }
        guard cropBox.count == 4 else {
            return "crop_box must contain exactly four coordinates"
        }
        guard cropBox[2] > cropBox[0], cropBox[3] > cropBox[1] else {
            return "crop_box must satisfy x2>x1 and y2>y1"
        }
        return nil
    }

    static func parsePerceptionFrame(
        from response: VisionParseResponse,
        screenWidth: Double,
        screenHeight: Double,
        timestamp: String
    ) -> Result<VisionPerceptionFrame, [String]> {
        var violations: [String] = []
        if let error = response.error?.trimmingCharacters(in: .whitespacesAndNewlines),
            !error.isEmpty
        {
            violations.append("Vision sidecar reported parse error: \(error)")
        }

        guard let elements = response.elements else {
            violations.append("Vision parse response is missing elements")
            return .failure(violations)
        }

        if let count = response.count, count != elements.count {
            violations.append(
                "Vision parse response count \(count) did not match element payload count \(elements.count)"
            )
        }

        let detections = elements.compactMap { element -> VisionDetection? in
            guard let frame = element.frame else {
                violations.append(
                    "Vision parse element '\(element.id)' returned an invalid box payload")
                return nil
            }
            return VisionDetection(
                id: element.id,
                elementType: element.type,
                frame: frame,
                confidence: element.confidence,
                text: element.text,
                source: element.source,
                timestamp: timestamp
            )
        }

        let overallConfidence: Double
        if detections.isEmpty {
            overallConfidence = 0
        } else {
            overallConfidence = detections.map(\.confidence).reduce(0, +) / Double(detections.count)
        }

        let frame = VisionPerceptionFrame(
            detections: detections,
            overallConfidence: overallConfidence,
            timestamp: timestamp,
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )

        violations.append(contentsOf: VisionContractValidator.validate(frame))
        return violations.isEmpty ? .success(frame) : .failure(violations)
    }

    private static func encodeJSONObject<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return dict
    }
}
