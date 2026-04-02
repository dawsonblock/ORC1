// AXScanner+Screenshot.swift — oracle_screenshot implementation.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - oracle_screenshot

    /// Take a screenshot of an app window.
    public static func screenshot(appName: String?, fullResolution: Bool) -> ToolResult {
        let targetApp: NSRunningApplication
        if let appName {
            guard let app = findApp(named: appName) else {
                return ToolResult(success: false, error: "Application '\(appName)' not found")
            }
            targetApp = app
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return ToolResult(success: false, error: "No frontmost application")
            }
            targetApp = frontApp
        }

        let pid = targetApp.processIdentifier
        let appDisplayName = targetApp.localizedName ?? appName ?? "app"

        // First attempt: try capturing without focus change.
        // With .optionAll this now finds windows even behind other windows.
        let (firstResult, firstFailure) = ScreenCapture.captureWindowSyncWithReason(
            pid: pid, fullResolution: fullResolution
        )
        if let firstResult {
            return screenshotResult(firstResult)
        }

        // Handle failures that activating the app cannot fix.
        switch firstFailure {
        case .noPermission:
            return ToolResult(
                success: false,
                error: "Screen Recording permission not granted",
                suggestion: "Grant Screen Recording in System Settings > Privacy & Security > Screen Recording, then restart Oracle OS."
            )
        case .windowListUnavailable:
            return ToolResult(
                success: false,
                error: "CGWindowListCopyWindowInfo returned nil — system error",
                suggestion: "This is unusual. Try restarting Oracle OS."
            )
        case .noWindowsForApp:
            break  // Activate and retry
        case .captureReturnedNil:
            break  // Window found but capture failed — activate and retry
        case .imageTooSmall:
            Log.info("Screenshot: window appears minimized — activating '\(appDisplayName)' to capture")
            break
        case nil:
            break
        }

        // Retry: activate the app to bring its windows on-screen, then capture.
        Log.info("Screenshot: retrying after focus for \(appDisplayName)")
        targetApp.activate()
        Thread.sleep(forTimeInterval: 0.5)  // Allow Space transition to complete

        let (retryResult, retryFailure) = ScreenCapture.captureWindowSyncWithReason(
            pid: pid, fullResolution: fullResolution
        )

        guard let retryResult else {
            let errorMsg: String
            let suggestion: String
            switch retryFailure {
            case .noPermission:
                errorMsg = "Screen Recording permission not granted"
                suggestion = "Grant Screen Recording in System Settings > Privacy & Security > Screen Recording, then restart Oracle OS."
            case .noWindowsForApp:
                errorMsg = "Application '\(appDisplayName)' has no open windows"
                suggestion = "The app is running but has no windows. Open a window first, or check oracle_state to verify."
            case .captureReturnedNil(let wid):
                errorMsg = "Window capture failed for '\(appDisplayName)' (windowID \(wid)) — window may be in an unsupported state"
                suggestion = "Try oracle_focus on the app first, wait a moment, then retry oracle_screenshot."
            case .imageTooSmall(let w, let h):
                errorMsg = "Window appears minimized for '\(appDisplayName)' (captured \(w)x\(h))"
                suggestion = "The window may be minimized. Use oracle_window action:\"restore\" to un-minimize it, then retry."
            default:
                errorMsg = "Screenshot capture failed for '\(appDisplayName)'"
                suggestion = "Ensure Screen Recording permission is granted in System Settings > Privacy & Security > Screen Recording."
            }
            return ToolResult(success: false, error: errorMsg, suggestion: suggestion)
        }

        return screenshotResult(retryResult)
    }

    private static func screenshotResult(_ result: ScreenshotResult) -> ToolResult {
        ToolResult(
            success: true,
            data: [
                "image": result.base64PNG,
                "width": result.width,
                "height": result.height,
                "window_title": result.windowTitle as Any,
                "mime_type": result.mimeType,
                "window_frame": [
                    "x": result.windowX,
                    "y": result.windowY,
                    "width": result.windowWidth,
                    "height": result.windowHeight,
                ],
            ]
        )
    }

    // MARK: - Synchronous Screenshot Helper

    /// Capture a screenshot synchronously using CGWindowListCreateImage.
    private static func captureScreenshotSync(
        pid: pid_t,
        fullResolution: Bool
    ) -> ScreenshotResult? {
        ScreenCapture.captureWindowSync(pid: pid, fullResolution: fullResolution)
    }
}
