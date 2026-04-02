// AXScanner+Shared.swift — Internal shared helpers used by multiple AXScanner extension files.
// All members are internal so extension files in other files can call them.

import AppKit
import AXorcist
import Foundation

@MainActor
extension AXScanner {

    // MARK: - App Lookup

    static func findApp(named name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveContains(name) == true
        }
    }

    static func appElement(for name: String) -> Element? {
        guard let app = findApp(named: name) else { return nil }
        return Element.application(for: app.processIdentifier)
    }

    // MARK: - Value Reading

    static func readValue(from element: Element) -> String? {
        if let val = element.value() {
            if let str = val as? String, !str.isEmpty { return str }
        }
        if let cfValue = element.rawAttributeValue(named: "AXValue") {
            if let str = cfValue as? String, !str.isEmpty { return str }
            if CFGetTypeID(cfValue) == CFStringGetTypeID() {
                let str = cfValue as! String
                if !str.isEmpty { return str }
            }
        }
        return nil
    }

    // MARK: - Web Area / URL

    static func findWebArea(in element: Element, depth: Int = 0) -> Element? {
        guard depth < 10 else { return nil }
        if element.role() == "AXWebArea" { return element }
        guard let children = element.children() else { return nil }
        for child in children {
            if let webArea = findWebArea(in: child, depth: depth + 1) {
                return webArea
            }
        }
        return nil
    }

    static func readURL(from element: Element) -> String? {
        if let url = element.url() {
            return url.absoluteString
        }
        if let cfValue = element.rawAttributeValue(named: "AXURL") {
            if let url = cfValue as? URL { return url.absoluteString }
            if CFGetTypeID(cfValue) == CFURLGetTypeID() {
                return (cfValue as! URL).absoluteString
            }
        }
        return nil
    }

    // MARK: - Semantic Content Check (used by Find + Read)

    static func hasSemanticContent(_ element: Element) -> Bool {
        let role = element.role() ?? ""
        let layoutRoles: Set<String> = [
            "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
            "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
            "AXLandmarkBanner", "AXLandmarkContentInfo",
        ]
        if layoutRoles.contains(role) {
            if element.title() != nil { return true }
            if readValue(from: element) != nil { return true }
            if element.descriptionText() != nil { return true }
            return false
        }
        return true
    }

    // MARK: - Element Summary + Full Info (used by Find + Inspect)

    static func elementSummary(_ element: Element) -> [String: Any] {
        var info: [String: Any] = [:]
        if let role = element.role() { info["role"] = role }
        if let name = element.computedName() { info["name"] = name }
        else if let title = element.title() { info["name"] = title }
        if let pos = element.position() { info["position"] = ["x": Int(pos.x), "y": Int(pos.y)] }
        if let size = element.size() { info["size"] = ["width": Int(size.width), "height": Int(size.height)] }
        info["actionable"] = element.isActionable()
        if let actions = element.supportedActions(), !actions.isEmpty {
            info["actions"] = actions
        }
        if let domId = readDOMId(from: element) { info["dom_id"] = domId }
        if let identifier = element.identifier() { info["identifier"] = identifier }
        return info
    }

    static func fullElementInfo(_ element: Element) -> [String: Any] {
        var info: [String: Any] = [:]
        if let role = element.role() { info["role"] = role }
        if let subrole = element.subrole() { info["subrole"] = subrole }
        if let title = element.title() { info["title"] = title }
        if let name = element.computedName() { info["computed_name"] = name }
        if let identifier = element.identifier() { info["identifier"] = identifier }
        if let desc = element.descriptionText() { info["description"] = desc }
        if let help = element.help() { info["help"] = help }
        if let domId = readDOMId(from: element) { info["dom_id"] = domId }
        if let domClasses = readDOMClasses(from: element) { info["dom_classes"] = domClasses }
        if let pos = element.position() { info["position"] = ["x": Int(pos.x), "y": Int(pos.y)] }
        if let size = element.size() { info["size"] = ["width": Int(size.width), "height": Int(size.height)] }
        if let frame = element.frame() {
            info["frame"] = ["x": Int(frame.origin.x), "y": Int(frame.origin.y),
                             "width": Int(frame.width), "height": Int(frame.height)]
        }
        info["actionable"] = element.isActionable()
        info["editable"] = element.isEditable()
        if let enabled = element.isEnabled() { info["enabled"] = enabled }
        if let focused = element.isFocused() { info["focused"] = focused }
        if let hidden = element.isHidden() { info["hidden"] = hidden }
        if let busy = element.isElementBusy() { info["busy"] = busy }
        if let modal = element.isModal() { info["modal"] = modal }
        if let actions = element.supportedActions(), !actions.isEmpty {
            info["supported_actions"] = actions
        }
        let elementRole = element.role() ?? ""
        if elementRole != "AXTextArea" {
            if let value = readValue(from: element) {
                if value.count > 500 {
                    info["value"] = String(value.prefix(500)) + "..."
                    info["value_length"] = value.count
                } else {
                    info["value"] = value
                }
            }
        } else {
            if let numChars = element.numberOfCharacters() {
                info["value_length"] = numChars
                info["value"] = "(text area with \(numChars) characters - use oracle_read to extract content)"
            }
        }
        if let selectedText = element.selectedText() {
            info["selected_text"] = selectedText.count > 200 ? String(selectedText.prefix(200)) + "..." : selectedText
        }
        if let placeholder = element.placeholderValue() { info["placeholder"] = placeholder }
        if let children = element.children() { info["child_count"] = children.count }
        if let parent = element.parent(), let parentRole = parent.role() { info["parent_role"] = parentRole }
        return info
    }

    // MARK: - DOM Helpers (used by Find + Inspect)

    static func findByDOMId(_ domId: String, in root: Element, maxDepth: Int) -> Element? {
        findByDOMIdWalk(element: root, domId: domId, depth: 0, maxDepth: max(maxDepth, 50))
    }

    static func findByDOMIdWalk(element: Element, domId: String, depth: Int, maxDepth: Int) -> Element? {
        guard depth < maxDepth else { return nil }
        if let elDomId = readDOMId(from: element), elDomId == domId { return element }
        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findByDOMIdWalk(element: child, domId: domId, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }
        return nil
    }

    static func readDOMId(from element: Element) -> String? {
        element.rawAttributeValue(named: "AXDOMIdentifier") as? String
    }

    static func readDOMClasses(from element: Element) -> String? {
        if let cfValue = element.rawAttributeValue(named: "AXDOMClassList") {
            if let str = cfValue as? String { return str }
            if let arr = cfValue as? [String] { return arr.joined(separator: " ") }
        }
        return nil
    }
}
