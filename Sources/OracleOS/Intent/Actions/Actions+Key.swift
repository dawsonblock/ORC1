// Actions+Key.swift — oracle_press, oracle_hotkey, oracle_focus implementations

import AXorcist
import Foundation

@MainActor
extension Actions {

    // MARK: - oracle_press

    /// Press a single key with optional modifiers.
    public static func pressKey(
        key: String,
        modifiers: [String]?,
        appName: String?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_press"
    ) -> ToolResult {
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.press(
                app: appName,
                key: key,
                modifiers: modifiers,
                postconditions: inferredPressPostconditions(appName: appName)
            ),
            approvalToken: approvalRequestID
        )
    }

    static func performPressKey(
        key: String,
        modifiers: [String]?,
        appName: String?
    ) -> ToolResult {
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            if let modifiers, !modifiers.isEmpty {
                try Element.performHotkey(keys: modifiers + [key])
                FocusManager.clearModifierFlags()
                usleep(10_000)
            } else if let specialKey = mapSpecialKey(key) {
                try Element.typeKey(specialKey)
            } else if key.count == 1 {
                try Element.typeText(key)
            } else {
                return ToolResult(
                    success: false,
                    error: "Unknown key: '\(key)'",
                    suggestion: "Valid: return, tab, escape, space, delete, up, down, left, right, f1-f12"
                )
            }
            return ToolResult(success: true, data: ["key": key])
        } catch {
            return ToolResult(success: false, error: "Key press failed: \(error)")
        }
    }

    // MARK: - oracle_focus

    public static func focusApp(
        appName: String,
        windowTitle: String? = nil,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_focus"
    ) -> ToolResult {
        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.focus(
                app: appName,
                windowTitle: windowTitle,
                postconditions: inferredFocusPostconditions(appName: appName, windowTitle: windowTitle)
            ),
            approvalToken: approvalRequestID
        )
    }

    static func performFocusApp(
        appName: String,
        windowTitle: String? = nil
    ) -> ToolResult {
        FocusManager.focus(appName: appName, windowTitle: windowTitle)
    }

    // MARK: - oracle_hotkey

    /// Press a key combination. Clears modifier flags after to prevent stuck keys.
    public static func hotkey(
        keys: [String],
        appName: String?,
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface = .mcp,
        approvalRequestID: String? = nil,
        taskID: String? = nil,
        toolName: String? = "oracle_hotkey"
    ) -> ToolResult {
        guard !keys.isEmpty else {
            return ToolResult(success: false, error: "Keys array cannot be empty")
        }

        _ = taskID
        _ = toolName
        return executeThroughRuntime(
            runtime: runtime,
            surface: surface,
            actionIntent: ActionIntent.hotkey(
                app: appName,
                keys: keys,
                postconditions: inferredPressPostconditions(appName: appName)
            ),
            approvalToken: approvalRequestID
        )
    }

    static func performHotkey(
        keys: [String],
        appName: String?
    ) -> ToolResult {
        if let appName {
            _ = FocusManager.focus(appName: appName)
            Thread.sleep(forTimeInterval: 0.2)
        }

        do {
            try Element.performHotkey(keys: keys)
            // Clear modifier flags IMMEDIATELY after the key events.
            // v1's proven order: clear first, delay after.
            FocusManager.clearModifierFlags()
            usleep(10_000)  // 10ms for clear event to propagate
            usleep(200_000) // 200ms for app to process the hotkey result
            return ToolResult(success: true, data: ["keys": keys])
        } catch {
            FocusManager.clearModifierFlags()
            return ToolResult(success: false, error: "Hotkey \(keys.joined(separator: "+")) failed: \(error)")
        }
    }

    // MARK: - Special Key Mapping

    static func mapSpecialKey(_ key: String) -> SpecialKey? {
        switch key.lowercased() {
        case "return", "enter": .return
        case "tab": .tab
        case "escape", "esc": .escape
        case "space": .space
        case "delete", "backspace": .delete
        case "up": .up
        case "down": .down
        case "left": .left
        case "right": .right
        case "home": .home
        case "end": .end
        case "pageup": .pageUp
        case "pagedown": .pageDown
        case "f1": .f1;  case "f2": .f2;  case "f3": .f3
        case "f4": .f4;  case "f5": .f5;  case "f6": .f6
        case "f7": .f7;  case "f8": .f8;  case "f9": .f9
        case "f10": .f10; case "f11": .f11; case "f12": .f12
        default: nil
        }
    }
}
