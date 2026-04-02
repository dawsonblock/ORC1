// AXScanner+Inspect.swift — oracle_inspect + oracle_element_at implementations.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - oracle_inspect

    /// Full metadata about one element.
    public static func inspect(
        query: String,
        role: String?,
        domId: String?,
        appName: String?
    ) -> ToolResult {
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

        let element: Element?
        if let domId {
            element = findByDOMId(domId, in: searchRoot, maxDepth: OracleConstants.semanticDepthBudget)
        } else {
            var options = ElementSearchOptions()
            options.maxDepth = OracleConstants.semanticDepthBudget
            if let role { options.includeRoles = [role] }
            element = searchRoot.findElement(matching: query, options: options)
        }

        guard let element else {
            return ToolResult(
                success: false,
                error: "Element '\(query)' not found",
                suggestion: "Try oracle_find to see what elements are available, or oracle_context for orientation"
            )
        }

        return ToolResult(success: true, data: fullElementInfo(element))
    }

    // MARK: - oracle_element_at

    /// Get element at screen coordinates.
    public static func elementAt(x: Double, y: Double) -> ToolResult {
        let point = CGPoint(x: x, y: y)

        guard let element = Element.elementAtPoint(point) else {
            return ToolResult(
                success: false,
                error: "No element found at (\(Int(x)), \(Int(y)))",
                suggestion: "Coordinates may be outside any window. Use oracle_state to see window positions."
            )
        }

        return ToolResult(success: true, data: fullElementInfo(element))
    }
}
