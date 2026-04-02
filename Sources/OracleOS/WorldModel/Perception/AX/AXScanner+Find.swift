// AXScanner+Find.swift — oracle_find implementation with CDP + vision fallbacks.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - oracle_find

    public static func findElements(
        query: String?,
        role: String?,
        domId: String?,
        domClass: String?,
        identifier: String?,
        appName: String?,
        depth: Int?
    ) -> ToolResult {
        // Need at least one search criterion
        guard query != nil || role != nil || domId != nil || identifier != nil || domClass != nil else {
            return ToolResult(
                success: false,
                error: "At least one search parameter required (query, role, dom_id, identifier, or dom_class)",
                suggestion: "Use oracle_context to see what's on screen first"
            )
        }

        // Find the app element to search within
        let searchRoot: Element
        if let appName {
            guard let app = findApp(named: appName),
                  let appElement = Element.application(for: app.processIdentifier)
            else {
                return ToolResult(
                    success: false,
                    error: "Application '\(appName)' not found",
                    suggestion: "Use oracle_state to see all running apps"
                )
            }
            searchRoot = appElement
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  let appElement = Element.application(for: frontApp.processIdentifier)
            else {
                return ToolResult(success: false, error: "No frontmost application accessible")
            }
            searchRoot = appElement
        }

        let maxDepth = min(depth ?? OracleConstants.semanticDepthBudget, OracleConstants.maxSearchDepth)

        // Set per-element timeout for this search. Deep tree walks on Chrome
        // can hang on individual AX calls; this ensures each call returns
        // within 3 seconds rather than blocking forever.
        setElementTimeout(searchRoot, seconds: 3.0)
        defer { resetElementTimeout(searchRoot) }

        // Strategy 1: DOM ID (most precise, bypasses depth limits)
        if let domId {
            if let element = findByDOMId(domId, in: searchRoot, maxDepth: maxDepth) {
                return ToolResult(success: true, data: ["elements": [elementSummary(element)], "count": 1])
            }
            return ToolResult(
                success: true,
                data: ["elements": [] as [Any], "count": 0],
                suggestion: "No element with DOM id '\(domId)' found. Try oracle_read to see what's on the page."
            )
        }

        // Strategy 2: AXorcist's search with ElementSearchOptions
        var options = ElementSearchOptions()
        options.maxDepth = maxDepth
        options.caseInsensitive = true
        if let role {
            options.includeRoles = [role]
        }

        var results: [Element] = []

        if let identifier {
            if let el = searchRoot.findElement(byIdentifier: identifier) {
                results = [el]
            }
        } else if let query {
            results = searchRoot.searchElements(matching: query, options: options)
        } else if let role {
            results = searchRoot.searchElements(byRole: role, options: options)
        }

        // Also try semantic-depth search if AXorcist search yields nothing
        if results.isEmpty, let query {
            results = semanticDepthSearch(query: query, role: role, in: searchRoot, maxDepth: maxDepth)
        }

        // CDP fallback: if AX search found nothing and we're in Chrome/Electron,
        // try Chrome DevTools Protocol for instant DOM-based element finding.
        if results.isEmpty, let query {
            if let cdpResults = cdpFallbackFind(query: query, appName: appName) {
                return ToolResult(
                    success: true,
                    data: [
                        "elements": cdpResults,
                        "count": cdpResults.count,
                        "total_matches": cdpResults.count,
                        "source": "cdp-fallback",
                    ],
                    suggestion: "Elements found via Chrome DevTools Protocol (AX tree search found nothing). " +
                                "Use oracle_click with the x/y coordinates shown in the position field."
                )
            }
        }

        // Vision fallback: if AX and CDP both failed, try VLM grounding.
        if results.isEmpty, let query {
            if let visionResults = VisionScanner.visionFallbackFind(
                query: query,
                appName: appName
            ) {
                return ToolResult(
                    success: true,
                    data: [
                        "elements": visionResults,
                        "count": visionResults.count,
                        "total_matches": visionResults.count,
                        "source": "vision-fallback",
                    ],
                    suggestion: "Elements found by VLM vision grounding (AX tree search found nothing). " +
                                "Use oracle_click with the x/y coordinates shown in the position field."
                )
            }
        }

        // Deduplicate by element identity (Chrome multiple windows cause duplicates)
        var seen = Set<Int>()
        var unique: [Element] = []
        for el in results {
            let hash = el.hashValue
            if seen.insert(hash).inserted {
                unique.append(el)
            }
        }

        // Cap results to avoid huge responses
        let capped = Array(unique.prefix(50))
        let summaries = capped.map { elementSummary($0) }

        return ToolResult(
            success: true,
            data: [
                "elements": summaries,
                "count": summaries.count,
                "total_matches": results.count,
            ]
        )
    }

    // MARK: - CDP Fallback

    /// Try finding elements via Chrome DevTools Protocol.
    /// Only works when Chrome is running with --remote-debugging-port=9222.
    private static func cdpFallbackFind(query: String, appName: String?) -> [[String: Any]]? {
        guard DOMScanner.isAvailable() else { return nil }
        guard let cdpElements = DOMScanner.findElements(query: query) else { return nil }
        guard !cdpElements.isEmpty else { return nil }

        let windowOrigin = chromeWindowOrigin(appName: appName)

        return cdpElements.map { el in
            let viewportX = el["centerX"] as? Int ?? 0
            let viewportY = el["centerY"] as? Int ?? 0
            let screenCoords = DOMScanner.viewportToScreen(
                viewportX: Double(viewportX),
                viewportY: Double(viewportY),
                windowX: windowOrigin.x,
                windowY: windowOrigin.y
            )

            var result: [String: Any] = [
                "name": el["ariaLabel"] as? String ??
                        el["text"] as? String ??
                        el["tag"] as? String ?? "unknown",
                "role": mapCDPRole(el),
                "position": ["x": Int(screenCoords.x), "y": Int(screenCoords.y)],
                "size": ["width": el["width"] as? Int ?? 0, "height": el["height"] as? Int ?? 0],
                "actionable": el["actionable"] as? Bool ?? false,
                "source": "cdp",
                "match_type": el["matchType"] as? String ?? "unknown",
            ]
            if let domId = el["id"] as? String, !domId.isEmpty { result["dom_id"] = domId }
            if let className = el["className"] as? String, !className.isEmpty { result["dom_class"] = className }
            return result
        }
    }

    private static func chromeWindowOrigin(appName: String?) -> (x: Double, y: Double) {
        let name = appName ?? "Chrome"
        guard let app = findApp(named: name),
              let appElement = Element.application(for: app.processIdentifier),
              let window = appElement.focusedWindow(),
              let pos = window.position()
        else { return (x: 0, y: 0) }
        return (x: Double(pos.x), y: Double(pos.y))
    }

    private static func mapCDPRole(_ element: [String: Any]) -> String {
        let tag = element["tag"] as? String ?? ""
        let role = element["role"] as? String ?? ""
        if !role.isEmpty {
            switch role {
            case "button": return "AXButton"
            case "link": return "AXLink"
            case "textbox": return "AXTextField"
            case "tab": return "AXTab"
            case "checkbox": return "AXCheckBox"
            case "radio": return "AXRadioButton"
            case "combobox": return "AXComboBox"
            default: return "AX\(role.prefix(1).uppercased())\(role.dropFirst())"
            }
        }
        switch tag {
        case "button": return "AXButton"
        case "a": return "AXLink"
        case "input": return "AXTextField"
        case "textarea": return "AXTextArea"
        case "select": return "AXPopUpButton"
        default: return "CDPElement"
        }
    }

    // MARK: - Semantic Depth Search

    private static func semanticDepthSearch(
        query: String,
        role: String?,
        in root: Element,
        maxDepth: Int
    ) -> [Element] {
        var results: [Element] = []
        semanticSearchWalk(
            element: root, query: query.lowercased(), role: role,
            results: &results, semanticDepth: 0, maxDepth: maxDepth
        )
        return results
    }

    private static func semanticSearchWalk(
        element: Element,
        query: String,
        role: String?,
        results: inout [Element],
        semanticDepth: Int,
        maxDepth: Int
    ) {
        guard semanticDepth <= maxDepth, results.count < 50 else { return }

        let hasContent = hasSemanticContent(element)
        let currentDepth = hasContent ? semanticDepth + 1 : semanticDepth

        if let role, element.role() != role {
            // Role doesn't match, skip this element but keep searching children
        } else {
            let name = element.computedName()?.lowercased() ?? ""
            let title = element.title()?.lowercased() ?? ""
            let value = readValue(from: element)?.lowercased() ?? ""
            let desc = element.descriptionText()?.lowercased() ?? ""
            let identifier = element.identifier()?.lowercased() ?? ""

            if name.contains(query) || title.contains(query) || value.contains(query)
                || desc.contains(query) || identifier.contains(query)
            {
                results.append(element)
            }
        }

        guard let children = element.children() else { return }
        for child in children {
            semanticSearchWalk(
                element: child, query: query, role: role,
                results: &results, semanticDepth: currentDepth, maxDepth: maxDepth
            )
        }
    }
}
