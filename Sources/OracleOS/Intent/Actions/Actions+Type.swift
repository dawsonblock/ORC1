// Actions+Type.swift — oracle_type implementation

import AppKit
import AXorcist
import Foundation

@MainActor
extension Actions {

    // MARK: - oracle_type

    /// Type text into a field. Uses AXorcist's SetFocusedValue command for
    /// AX-native typing (focus + setValue), with synthetic typeText fallback.
    public static func typeText(
        text: String,
        into: String?,
        domId: String?,
        appName: String?,
        clear: Bool,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_type"
    ) -> ToolResult {
        _ = approvalRequestID
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.type(
                app: appName,
                into: into,
                domID: domId,
                text: text,
                clear: clear,
                postconditions: inferredTypePostconditions(text: text, into: into, domId: domId)
            )
        )
    }

    static func performTypeText(
        text: String,
        into: String?,
        domId: String?,
        appName: String?,
        clear: Bool
    ) -> ToolResult {
        if let fieldName = into ?? domId {
            let element: Element?
            if let domId {
                let locator = LocatorBuilder.build(domId: domId)
                element = findElement(locator: locator, appName: appName)
            } else if let into {
                element = findEditableField(named: into, appName: appName)
            } else {
                element = nil
            }

            guard let element else {
                return ToolResult(
                    success: false,
                    error: "Field '\(fieldName)' not found",
                    suggestion: "Use oracle_find to see available fields, or oracle_context for orientation"
                )
            }

            // Strategy 1: AX-native setValue
            if element.isAttributeSettable(named: "AXValue") {
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)

                if clear {
                    _ = element.setValue("", forAttribute: "AXValue")
                    Thread.sleep(forTimeInterval: 0.05)
                }

                let setOk = element.setValue(text, forAttribute: "AXValue")
                if setOk {
                    usleep(150_000)

                    var readBackRef: CFTypeRef?
                    let readBackOk = AXUIElementCopyAttributeValue(
                        element.underlyingElement,
                        "AXValue" as CFString,
                        &readBackRef
                    )
                    let readback: String?
                    if readBackOk == .success, let ref = readBackRef {
                        if let str = ref as? String, !str.isEmpty {
                            readback = str
                        } else if CFGetTypeID(ref) == CFStringGetTypeID() {
                            readback = (ref as! String)
                        } else {
                            readback = nil
                        }
                    } else {
                        readback = nil
                    }

                    let textPrefix = String(text.prefix(10))
                    if let readback, readback.contains(textPrefix) {
                        return ToolResult(
                            success: true,
                            data: [
                                "method": "ax-native-setValue",
                                "field": fieldName,
                                "typed": text,
                                "readback": String(readback.prefix(200)),
                            ]
                        )
                    }
                    Log.info("setValue for '\(fieldName)' readback doesn't match - falling back to click-then-type")
                }
            }

            // Strategy 2: Click + type
            if let appName {
                _ = FocusManager.focus(appName: appName)
                Thread.sleep(forTimeInterval: 0.2)
            }

            if element.isActionable() {
                do {
                    try element.click()
                    Thread.sleep(forTimeInterval: 0.15)
                } catch {
                    _ = element.setValue(true, forAttribute: "AXFocused")
                    Thread.sleep(forTimeInterval: 0.1)
                }
            } else {
                _ = element.setValue(true, forAttribute: "AXFocused")
                Thread.sleep(forTimeInterval: 0.1)
            }

            do {
                if clear {
                    try Element.performHotkey(keys: ["cmd", "a"])
                    Thread.sleep(forTimeInterval: 0.05)
                    try Element.typeKey(.delete)
                    Thread.sleep(forTimeInterval: 0.05)
                    FocusManager.clearModifierFlags()
                }
                try Element.typeText(text, delay: 0.01)
                Thread.sleep(forTimeInterval: 0.15)

                let readback = readbackFromElement(element)
                let textPrefix = String(text.prefix(10))
                let verified = readback.contains(textPrefix)
                return ToolResult(
                    success: true,
                    data: [
                        "method": "click-then-type",
                        "field": fieldName,
                        "typed": text,
                        "verified": verified,
                        "readback": readback,
                    ]
                )
            } catch {
                return ToolResult(success: false, error: "Type into '\(fieldName)' failed: \(error)")
            }
        }

        // No target field - type at current focus
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            if clear {
                try Element.performHotkey(keys: ["cmd", "a"])
                Thread.sleep(forTimeInterval: 0.05)
                try Element.typeKey(.delete)
                Thread.sleep(forTimeInterval: 0.05)
                FocusManager.clearModifierFlags()
            }
            try Element.typeText(text, delay: 0.01)
            Thread.sleep(forTimeInterval: 0.1)
            return ToolResult(
                success: true,
                data: ["method": "synthetic-at-focus", "typed": text]
            )
        } catch {
            return ToolResult(success: false, error: "Type failed: \(error)")
        }
    }
}
