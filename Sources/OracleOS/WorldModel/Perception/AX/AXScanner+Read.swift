// AXScanner+Read.swift — oracle_read implementation with semantic depth tunneling.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - oracle_read

    /// Read text content from screen using semantic depth tunneling.
    public static func readContent(appName: String?, query: String?, depth: Int?) -> ToolResult {
        let searchRoot: Element
        if let appName {
            guard let app = findApp(named: appName),
                  let appElement = Element.application(for: app.processIdentifier)
            else {
                return ToolResult(success: false, error: "Application '\(appName)' not found")
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

        let maxDepth = depth ?? OracleConstants.semanticDepthBudget

        // Set per-element timeout for the read operation.
        setElementTimeout(searchRoot, seconds: 3.0)
        defer { resetElementTimeout(searchRoot) }

        // If query provided, narrow to that element first
        var readRoot = searchRoot
        if let query {
            var options = ElementSearchOptions()
            options.maxDepth = maxDepth
            if let found = searchRoot.findElement(matching: query, options: options) {
                readRoot = found
            }
        } else {
            // For web apps, start from AXWebArea for better depth reach
            if let window = searchRoot.focusedWindow(),
               let webArea = findWebArea(in: window)
            {
                readRoot = webArea
            } else if let window = searchRoot.focusedWindow() {
                readRoot = window
            }
        }

        // Use semantic depth tunneling to extract content
        var items: [String] = []
        collectContent(from: readRoot, items: &items, semanticDepth: 0, maxSemanticDepth: maxDepth)

        return ToolResult(
            success: true,
            data: [
                "content": items.joined(separator: "\n"),
                "item_count": items.count,
            ]
        )
    }

    // MARK: - Semantic Depth Tunneling

    /// Collect text content with semantic depth tunneling.
    /// Empty layout containers (AXGroup with no content) are traversed at zero depth cost.
    private static func collectContent(
        from element: Element,
        items: inout [String],
        semanticDepth: Int,
        maxSemanticDepth: Int
    ) {
        guard semanticDepth <= maxSemanticDepth else { return }

        let hasContent = hasSemanticContent(element)
        let currentDepth = hasContent ? semanticDepth + 1 : semanticDepth

        if hasContent {
            var text = ""
            if element.role() != nil {
                if let value = readValue(from: element) {
                    text = value
                } else if let title = element.title() {
                    text = title
                } else if let name = element.computedName() {
                    text = name
                }
            }
            if !text.isEmpty {
                let role = element.role() ?? ""
                let prefix = role.hasPrefix("AXHeading") ? "# " :
                             role == "AXLink" ? "[link] " :
                             role == "AXButton" ? "[button] " : ""
                items.append("\(prefix)\(text)")
            }
        }

        guard let children = element.children() else { return }
        for child in children {
            collectContent(from: child, items: &items, semanticDepth: currentDepth, maxSemanticDepth: maxSemanticDepth)
        }
    }
}
