// Actions+Helpers.swift — Shared internal helpers for the Actions enum.
// All members are internal (not private) so other extension files can call them.

import AppKit
import AXorcist
import Foundation

@MainActor
extension Actions {

    // MARK: - Element Finding (shared)

    /// Find an element using content-root-first strategy with semantic depth.
    /// Searches AXWebArea first (in-page elements), then full app tree.
    static func findElement(locator: Locator, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        // Content-root-first: search AXWebArea, then full tree
        if let window = appElement.focusedWindow(),
           let webArea = AXScanner.findWebArea(in: window)
        {
            if let found = searchWithSemanticDepth(locator: locator, root: webArea) {
                return found
            }
        }

        // Full app tree fallback
        return searchWithSemanticDepth(locator: locator, root: appElement)
    }

    /// Search with semantic depth tunneling using AXorcist's Element.searchElements.
    /// Falls back to manual semantic-depth walk if AXorcist doesn't find it.
    static func searchWithSemanticDepth(locator: Locator, root: Element) -> Element? {
        // Try AXorcist's built-in search first
        if let query = locator.computedNameContains {
            var options = ElementSearchOptions()
            options.maxDepth = OracleConstants.semanticDepthBudget
            if let roleCriteria = locator.criteria.first(where: { $0.attribute == "AXRole" }) {
                options.includeRoles = [roleCriteria.value]
            }
            if let found = root.findElement(matching: query, options: options) {
                return found
            }
        }

        // DOM ID search (bypasses depth limits)
        if let domIdCriteria = locator.criteria.first(where: { $0.attribute == "AXDOMIdentifier" }) {
            return findByDOMId(domIdCriteria.value, in: root, maxDepth: 50)
        }

        return nil
    }

    /// Resolve app name to Element.
    static func resolveAppElement(appName: String?) -> Element? {
        if let appName {
            return AXScanner.appElement(for: appName)
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return Element.application(for: frontApp.processIdentifier)
    }

    // MARK: - Field Finding for oracle_type into

    /// Editable/input roles that the 'into' parameter should match against.
    static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXSecureTextField",
    ]

    /// Find an editable field by name. Searches ALL matching elements and
    /// scores them, preferring editable roles and exact/prefix matches.
    static func findEditableField(named query: String, appName: String?) -> Element? {
        guard let appElement = resolveAppElement(appName: appName) else { return nil }

        let queryLower = query.lowercased()

        let searchRoot: Element
        if let window = appElement.focusedWindow(),
           let webArea = AXScanner.findWebArea(in: window)
        {
            searchRoot = webArea
        } else if let window = appElement.focusedWindow() {
            searchRoot = window
        } else {
            searchRoot = appElement
        }

        var candidates: [(element: Element, score: Int)] = []
        scoreFieldCandidates(
            element: searchRoot,
            queryLower: queryLower,
            candidates: &candidates,
            semanticDepth: 0,
            maxSemanticDepth: OracleConstants.semanticDepthBudget
        )

        return candidates.max(by: { $0.score < $1.score })?.element
    }

    /// Layout roles that cost zero semantic depth (tunneled through).
    static let layoutRoles: Set<String> = [
        "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
        "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
        "AXLandmarkBanner", "AXLandmarkContentInfo",
    ]

    /// Walk the tree scoring elements as field candidates.
    static func scoreFieldCandidates(
        element: Element,
        queryLower: String,
        candidates: inout [(element: Element, score: Int)],
        semanticDepth: Int,
        maxSemanticDepth: Int
    ) {
        guard semanticDepth <= maxSemanticDepth, candidates.count < 100 else { return }

        let role = element.role() ?? ""
        let titleLower = (element.title() ?? "").lowercased()
        let descLower = (element.descriptionText() ?? "").lowercased()
        let nameLower = (element.computedName() ?? "").lowercased()

        let hasContent = !titleLower.isEmpty || !descLower.isEmpty || !nameLower.isEmpty
        let isTunnel = layoutRoles.contains(role) && !hasContent
        let childSemanticDepth = isTunnel ? semanticDepth : semanticDepth + 1

        var score = 0

        if titleLower == queryLower || descLower == queryLower || nameLower == queryLower {
            score = 100
        } else if titleLower.hasPrefix(queryLower) || descLower.hasPrefix(queryLower) || nameLower.hasPrefix(queryLower) {
            score = 80
        } else if titleLower.contains(queryLower) || descLower.contains(queryLower) || nameLower.contains(queryLower) {
            score = 60
        }

        if score > 0 {
            if editableRoles.contains(role) { score += 50 }

            if let pos = element.position(), let size = element.size() {
                let onScreen = NSScreen.screens.contains { screen in
                    screen.frame.intersects(CGRect(origin: pos, size: size))
                }
                if onScreen && size.width > 1 && size.height > 1 { score += 20 }
            }

            if score >= 50 {
                candidates.append((element: element, score: score))
            }
        }

        guard let children = element.children() else { return }
        for child in children {
            scoreFieldCandidates(
                element: child, queryLower: queryLower,
                candidates: &candidates,
                semanticDepth: childSemanticDepth,
                maxSemanticDepth: maxSemanticDepth
            )
        }
    }

    // MARK: - Readback Verification

    static func readbackFromElement(_ element: Element) -> String {
        if let value = AXScanner.readValue(from: element), !value.isEmpty {
            return value.count > 200 ? String(value.prefix(200)) + "..." : value
        }
        if let title = element.title(), !title.isEmpty {
            return title.count > 200 ? String(title.prefix(200)) + "..." : title
        }
        if let name = element.computedName(), !name.isEmpty {
            return name.count > 200 ? String(name.prefix(200)) + "..." : name
        }
        return "(verification unavailable for this field type)"
    }

    // MARK: - Inferred Postconditions

    static func inferredClickPostconditions(
        query: String?,
        role: String?,
        domId: String?
    ) -> [Postcondition] {
        let target = domId ?? query
        guard let target else { return [] }

        let editableRolesLocal = ["AXTextField", "AXTextArea", "AXComboBox"]
        if let role, editableRolesLocal.contains(role) {
            return [.elementFocused(target)]
        }
        return []
    }

    static func inferredTypePostconditions(
        text: String,
        into: String?,
        domId: String?
    ) -> [Postcondition] {
        guard let target = domId ?? into else { return [] }
        return [
            .elementFocused(target),
            .elementValueEquals(target, text),
        ]
    }

    static func inferredPressPostconditions(appName: String?) -> [Postcondition] {
        guard let appName else { return [] }
        return [.appFrontmost(appName)]
    }

    static func inferredFocusPostconditions(
        appName: String,
        windowTitle: String?
    ) -> [Postcondition] {
        var conditions: [Postcondition] = [.appFrontmost(appName)]
        if let windowTitle {
            conditions.append(.windowTitleContains(windowTitle))
        }
        return conditions
    }

    // MARK: - DOM ID Search

    static func findByDOMId(_ domId: String, in root: Element, maxDepth: Int) -> Element? {
        findByDOMIdWalk(element: root, domId: domId, depth: 0, maxDepth: maxDepth)
    }

    static func findByDOMIdWalk(element: Element, domId: String, depth: Int, maxDepth: Int) -> Element? {
        guard depth < maxDepth else { return nil }
        if let elDomId = element.rawAttributeValue(named: "AXDOMIdentifier") as? String, elDomId == domId {
            return element
        }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findByDOMIdWalk(element: child, domId: domId, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }
}
