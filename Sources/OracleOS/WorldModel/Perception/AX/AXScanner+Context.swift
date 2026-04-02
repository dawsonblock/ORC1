// AXScanner+Context.swift — oracle_context + oracle_state implementations.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - oracle_context

    /// Get orientation context: focused app, window, URL, focused element, visible interactive elements.
    public static func getContext(appName: String?) -> ToolResult {
        if let appName {
            guard let app = findApp(named: appName) else {
                return ToolResult(
                    success: false,
                    error: "Application '\(appName)' not found or not running",
                    suggestion: "Use oracle_state to see all running apps"
                )
            }
            return buildContext(for: app)
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return ToolResult(success: false, error: "No frontmost application found")
            }
            return buildContext(for: frontApp)
        }
    }

    // MARK: - oracle_state

    /// Get all running apps and their windows.
    public static func getState(appName: String?) -> ToolResult {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        if let appName {
            guard let app = apps.first(where: {
                $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
            }) else {
                return ToolResult(
                    success: false,
                    error: "Application '\(appName)' not found",
                    suggestion: "Use oracle_state without app parameter to see all running apps"
                )
            }
            return ToolResult(success: true, data: ["apps": [buildAppInfo(app)]])
        }

        let appInfos = apps.compactMap { buildAppInfo($0) }
        return ToolResult(success: true, data: [
            "app_count": appInfos.count,
            "apps": appInfos,
        ])
    }

    // MARK: - Private Context Builder

    private static func buildContext(for app: NSRunningApplication) -> ToolResult {
        let pid = app.processIdentifier
        let appLabel = app.localizedName ?? "Unknown"
        let observation = ObservationBuilder.capture(appName: appLabel)

        guard let appElement = Element.application(for: pid) else {
            return ToolResult(
                success: true,
                data: [
                    "app": appLabel,
                    "observation": observation.toDict(),
                    "note": "Could not read accessibility tree. App may need focus for native apps.",
                ],
                suggestion: "Try oracle_focus to bring the app to front first"
            )
        }

        // Set per-element timeout for context building. oracle_context walks
        // the interactive elements tree; a hung app would block the MCP server.
        setElementTimeout(appElement, seconds: 3.0)
        defer { resetElementTimeout(appElement) }

        var data: [String: Any] = [
            "app": appLabel,
            "bundle_id": app.bundleIdentifier ?? "unknown",
            "pid": pid,
            "observation": observation.toDict(),
        ]

        if let title = observation.windowTitle {
            data["window"] = title
        }
        if let url = observation.url {
            data["url"] = url
        }
        if let focused = observation.focusedElement {
            var focusedInfo: [String: Any] = [
                "id": focused.id,
                "source": focused.source.rawValue,
                "enabled": focused.enabled,
                "visible": focused.visible,
                "focused": focused.focused,
                "confidence": focused.confidence,
            ]
            if let role = focused.role { focusedInfo["role"] = role }
            if let label = focused.label { focusedInfo["name"] = label }
            if let value = focused.value { focusedInfo["value"] = value }
            data["focused_element"] = focusedInfo
        }
        if !observation.elements.isEmpty {
            data["interactive_elements"] = Array(observation.elements.prefix(30)).map { element in
                var summary: [String: Any] = [
                    "id": element.id,
                    "source": element.source.rawValue,
                    "enabled": element.enabled,
                    "visible": element.visible,
                    "focused": element.focused,
                    "confidence": element.confidence,
                ]
                if let role = element.role { summary["role"] = role }
                if let label = element.label { summary["name"] = label }
                if let value = element.value { summary["value"] = value }
                return summary
            }
        }

        return ToolResult(
            success: true,
            data: data,
            context: ContextInfo(
                app: app.localizedName,
                window: data["window"] as? String,
                url: data["url"] as? String
            )
        )
    }

    /// Collect interactive elements (buttons, links, fields) for context.
    private static func collectInteractiveElements(
        from element: Element,
        roles: Set<String>,
        results: inout [[String: String]],
        depth: Int,
        maxDepth: Int
    ) {
        guard depth < maxDepth, results.count < 30 else { return }

        if let role = element.role(), roles.contains(role) {
            var info: [String: String] = ["role": role]
            if let name = element.computedName() { info["name"] = name }
            else if let title = element.title() { info["name"] = title }
            if info["name"] != nil {
                results.append(info)
            }
        }

        guard let children = element.children() else { return }
        for child in children {
            collectInteractiveElements(from: child, roles: roles, results: &results, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private static func buildAppInfo(_ app: NSRunningApplication) -> [String: Any] {
        var info: [String: Any] = [
            "name": app.localizedName ?? "Unknown",
            "bundle_id": app.bundleIdentifier ?? "unknown",
            "pid": app.processIdentifier,
            "active": app.isActive,
        ]

        if let appElement = Element.application(for: app.processIdentifier) {
            // Use timeout-protected window listing. Some apps (especially
            // hung ones) block forever on AXWindows. 2s is plenty for
            // a simple attribute read.
            if let windows = appElement.windowsWithTimeout(timeout: 2.0) {
                let windowInfos: [[String: Any]] = windows.compactMap { win in
                    var w: [String: Any] = [:]
                    if let title = win.title() { w["title"] = title }
                    if let pos = win.position() { w["position"] = ["x": pos.x, "y": pos.y] }
                    if let size = win.size() { w["size"] = ["width": size.width, "height": size.height] }
                    return w.isEmpty ? nil : w
                }
                if !windowInfos.isEmpty {
                    info["windows"] = windowInfos
                }
            }
        }

        return info
    }
}
