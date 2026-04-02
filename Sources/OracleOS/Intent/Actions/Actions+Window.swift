// Actions+Window.swift — oracle_window, oracle_focus implementations

import AXorcist
import Foundation

@MainActor
extension Actions {

    // MARK: - oracle_window

    /// Window management operations.
    public static func manageWindow(
        action: String,
        appName: String,
        windowTitle: String?,
        x: Double?, y: Double?,
        width: Double?, height: Double?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_window"
    ) -> ToolResult {
        if action.lowercased() == "list" {
            return performWindowAction(
                action: action,
                appName: appName,
                windowTitle: windowTitle,
                x: x,
                y: y,
                width: width,
                height: height
            )
        }

        _ = approvalRequestID
        _ = taskID
        _ = toolName

        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.manageWindow(
                app: appName,
                action: action,
                windowTitle: windowTitle,
                x: x,
                y: y,
                width: width,
                height: height,
                postconditions: inferredFocusPostconditions(appName: appName, windowTitle: windowTitle)
            )
        )
    }

    static func performWindowAction(
        action: String,
        appName: String,
        windowTitle: String?,
        x: Double?, y: Double?,
        width: Double?, height: Double?
    ) -> ToolResult {
        guard let appElement = AXScanner.appElement(for: appName) else {
            return ToolResult(success: false, error: "Application '\(appName)' not found")
        }

        if action == "list" {
            guard let windows = appElement.windows() else {
                return ToolResult(success: true, data: ["windows": [] as [Any], "count": 0])
            }
            let infos: [[String: Any]] = windows.compactMap { win in
                var info: [String: Any] = [:]
                if let title = win.title() { info["title"] = title }
                if let pos = win.position() { info["position"] = ["x": Int(pos.x), "y": Int(pos.y)] }
                if let size = win.size() { info["size"] = ["width": Int(size.width), "height": Int(size.height)] }
                if let minimized = win.isMinimized() { info["minimized"] = minimized }
                if let fullscreen = win.isFullScreen() { info["fullscreen"] = fullscreen }
                return info.isEmpty ? nil : info
            }
            return ToolResult(success: true, data: ["windows": infos, "count": infos.count])
        }

        let window: Element? = if let windowTitle {
            appElement.windows()?.first { $0.title()?.localizedCaseInsensitiveContains(windowTitle) == true }
        } else {
            appElement.focusedWindow() ?? appElement.mainWindow()
        }

        guard let window else {
            return ToolResult(
                success: false,
                error: "Window not found in '\(appName)'",
                suggestion: "Use oracle_window with action:'list' to see windows"
            )
        }

        switch action.lowercased() {
        case "minimize":
            _ = window.minimizeWindow()
            return ToolResult(success: true, data: ["action": "minimize"])
        case "maximize":
            _ = window.maximizeWindow()
            return ToolResult(success: true, data: ["action": "maximize"])
        case "close":
            _ = window.closeWindow()
            return ToolResult(success: true, data: ["action": "close"])
        case "restore":
            _ = window.showWindow()
            return ToolResult(success: true, data: ["action": "restore"])
        case "move":
            guard let x, let y else {
                return ToolResult(success: false, error: "move requires x and y parameters")
            }
            _ = window.moveWindow(to: CGPoint(x: x, y: y))
            return ToolResult(success: true, data: ["action": "move", "x": x, "y": y])
        case "resize":
            guard let width, let height else {
                return ToolResult(success: false, error: "resize requires width and height parameters")
            }
            _ = window.resizeWindow(to: CGSize(width: width, height: height))
            return ToolResult(success: true, data: ["action": "resize", "width": width, "height": height])
        default:
            return ToolResult(success: false, error: "Unknown action: '\(action)'")
        }
    }
}
