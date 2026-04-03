// Actions+Click.swift — oracle_click implementation

import AppKit
import AXorcist
import Foundation

@MainActor
extension Actions {

    // MARK: - oracle_click

    /// Click an element. AX-native first via AXorcist's PerformAction command,
    /// synthetic fallback with position-based click.
    public static func click(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        button: String?,
        count: Int?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_click"
    ) -> ToolResult {
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.click(
                app: appName,
                query: query,
                role: role,
                domID: domId,
                x: x,
                y: y,
                button: button,
                count: count,
                postconditions: inferredClickPostconditions(query: query, role: role, domId: domId)
            ),
            approvalToken: approvalRequestID
        )
    }

    static func performClick(
        query: String?,
        role: String?,
        domId: String?,
        appName: String?,
        x: Double?,
        y: Double?,
        button: String?,
        count: Int?
    ) -> ToolResult {
        let mouseButton: MouseButton = switch button {
        case "right": .right
        case "middle": .middle
        default: .left
        }
        let clickCount = max(1, count ?? 1)

        // Coordinate-based click (no element lookup)
        if let x, let y {
            if let appName {
                _ = FocusManager.focus(appName: appName)
                Thread.sleep(forTimeInterval: 0.2)
            }
            do {
                try InputDriver.click(at: CGPoint(x: x, y: y), button: mouseButton, count: clickCount)
                Thread.sleep(forTimeInterval: 0.15)
                return ToolResult(
                    success: true,
                    data: ["method": "coordinate", "x": x, "y": y]
                )
            } catch {
                return ToolResult(success: false, error: "Click at (\(Int(x)), \(Int(y))) failed: \(error)")
            }
        }

        // Element-based click needs query or domId
        guard query != nil || domId != nil else {
            return ToolResult(
                success: false,
                error: "Either query/dom_id or x/y coordinates required",
                suggestion: "Use oracle_find to locate elements, or oracle_element_at for coordinates"
            )
        }

        let locator = LocatorBuilder.build(query: query, role: role, domId: domId)
        let element = findElement(locator: locator, appName: appName)

        // Strategy 2.5a: CDP fallback
        if element == nil, let query {
            if DOMScanner.isAvailable(),
               let cdpElements = DOMScanner.findElements(query: query),
               let firstMatch = cdpElements.first
            {
                let viewportX = firstMatch["centerX"] as? Int ?? 0
                let viewportY = firstMatch["centerY"] as? Int ?? 0

                let windowOrigin: (x: Double, y: Double)
                if let appName,
                   let app = AXScanner.findApp(named: appName),
                   let appElement = Element.application(for: app.processIdentifier),
                   let window = appElement.focusedWindow(),
                   let pos = window.position()
                {
                    windowOrigin = (Double(pos.x), Double(pos.y))
                } else {
                    windowOrigin = (0, 0)
                }

                let screenCoords = DOMScanner.viewportToScreen(
                    viewportX: Double(viewportX),
                    viewportY: Double(viewportY),
                    windowX: windowOrigin.x,
                    windowY: windowOrigin.y
                )

                if let appName {
                    _ = FocusManager.focus(appName: appName)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                do {
                    try InputDriver.click(
                        at: CGPoint(x: screenCoords.x, y: screenCoords.y),
                        button: mouseButton,
                        count: clickCount
                    )
                    Thread.sleep(forTimeInterval: 0.15)
                    Log.info("CDP click: '\(query)' at (\(Int(screenCoords.x)), \(Int(screenCoords.y)))")
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "cdp-grounded",
                            "element": query,
                            "x": screenCoords.x,
                            "y": screenCoords.y,
                            "match_type": firstMatch["matchType"] as? String ?? "unknown",
                        ]
                    )
                } catch {
                    Log.warn("CDP click failed: \(error)")
                }
            }
        }

        // Strategy 2.5b: Vision fallback
        if element == nil, let query {
            if let visionResult = VisionScanner.visionFallbackClick(
                query: query,
                appName: appName
            ) {
                let vx = visionResult.data?["x"] as? Double ?? 0
                let vy = visionResult.data?["y"] as? Double ?? 0

                if let appName {
                    _ = FocusManager.focus(appName: appName)
                    Thread.sleep(forTimeInterval: 0.2)
                }

                do {
                    try InputDriver.click(
                        at: CGPoint(x: vx, y: vy),
                        button: mouseButton,
                        count: clickCount
                    )
                    Thread.sleep(forTimeInterval: 0.15)
                    return ToolResult(
                        success: true,
                        data: [
                            "method": "vlm-grounded",
                            "element": query,
                            "x": vx,
                            "y": vy,
                            "confidence": visionResult.data?["confidence"] as? Double ?? 0,
                            "inference_ms": visionResult.data?["inference_ms"] as? Int ?? 0,
                        ]
                    )
                } catch {
                    return ToolResult(
                        success: false,
                        error: "VLM-grounded click at (\(Int(vx)), \(Int(vy))) failed: \(error)"
                    )
                }
            }
        }

        guard let element else {
            return ToolResult(
                success: false,
                error: "Element '\(query ?? domId ?? "")' not found in \(appName ?? "frontmost app")",
                suggestion: "Use oracle_find to see what elements are available, or oracle_ground for visual search"
            )
        }

        if !element.isActionable() {
            return ToolResult(
                success: false,
                error: "Element '\(element.computedName() ?? query ?? "")' is not actionable",
                suggestion: "Element may be disabled, hidden, or off-screen. Use oracle_inspect to check."
            )
        }

        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            try element.click(button: mouseButton, clickCount: clickCount)
            Thread.sleep(forTimeInterval: 0.15)
            return ToolResult(
                success: true,
                data: [
                    "method": "synthetic",
                    "element": element.computedName() ?? query ?? "",
                ]
            )
        } catch {
            return ToolResult(
                success: false,
                error: "Click failed: \(error)",
                suggestion: "Try oracle_inspect on the element, or use x/y coordinates"
            )
        }
    }
}
