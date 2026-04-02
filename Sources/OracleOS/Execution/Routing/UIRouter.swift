import AppKit
import Foundation

public struct UIRouter: @unchecked Sendable {
    private let automationHost: AutomationHost?

    init(automationHost: AutomationHost?) {
        self.automationHost = automationHost
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> ExecutionOutcome {
        guard command.type == .ui else {
            throw RouterError.invalidRoute(expected: .ui, actual: command.type)
        }

        #if DEBUG
        if let automationHost = automationHost {
            NSLog("UIRouter executing with automation host: \(automationHost)")
        }
        #endif

        guard case .ui(let action) = command.payload else {
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid UI payload",
                policyDecision: policyDecision,
                router: "ui"
            )
        }

        let result = await MainActor.run { execute(action) }
        let observations = [
            ObservationPayload.uiAction(
                action: action.name,
                target: action.query ?? action.domID ?? action.app ?? action.windowTitle,
                result: result.summary
            ),
        ]

        if result.success {
            return CommandRouter.successOutcome(
                command: command,
                observations: observations,
                artifacts: [],
                policyDecision: policyDecision,
                router: "ui"
            )
        }

        return CommandRouter.failureOutcome(
            command: command,
            reason: result.error ?? result.summary,
            policyDecision: policyDecision,
            router: "ui"
        )
    }

    @MainActor
    private func execute(_ action: UIAction) -> ToolResult {
        switch action.name {
        case "click", "clickElement":
            return Actions.performClick(
                query: action.query,
                role: action.role,
                domId: action.domID,
                appName: action.app,
                x: action.x,
                y: action.y,
                button: action.button,
                count: action.count
            )
        case "type", "typeText":
            return Actions.performTypeText(
                text: action.text ?? "",
                into: action.query,
                domId: action.domID,
                appName: action.app,
                clear: action.clear ?? false
            )
        case "focus", "focusWindow", "launchApp":
            return Actions.performFocusApp(appName: action.app ?? "unknown", windowTitle: action.windowTitle)
        case "press":
            let modifiers = action.modifiers ?? action.role?.split(separator: "+").map(String.init)
            return Actions.performPressKey(key: action.query ?? "", modifiers: modifiers, appName: action.app)
        case "hotkey":
            let keys = action.modifiers
                ?? action.query?.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
                ?? []
            return Actions.performHotkey(keys: keys, appName: action.app)
        case "scroll", "scrollElement":
            return Actions.performScroll(
                direction: action.query ?? "down",
                amount: action.amount ?? action.count,
                appName: action.app,
                x: action.x,
                y: action.y
            )
        case "openURL":
            guard let rawURL = action.query, let url = URL(string: rawURL) else {
                return ToolResult(success: false, error: "Invalid URL: \(action.query ?? "nil")")
            }
            let opened = NSWorkspace.shared.open(url)
            return ToolResult(
                success: opened,
                data: opened ? ["url": rawURL] : nil,
                error: opened ? nil : "Failed to open URL '\(rawURL)'"
            )
        case "window", "manageWindow":
            return Actions.performWindowAction(
                action: action.query ?? "list",
                appName: action.app ?? "unknown",
                windowTitle: action.windowTitle,
                x: action.x,
                y: action.y,
                width: action.width,
                height: action.height
            )
        case "read", "readElement":
            return AXScanner.readContent(appName: action.app, query: action.query, depth: nil)
        default:
            return ToolResult(success: false, error: "Unsupported UI action: \(action.name)")
        }
    }
}

private extension ToolResult {
    var summary: String {
        if let summary = data?["summary"] as? String, !summary.isEmpty {
            return summary
        }
        if let error, !error.isEmpty {
            return error
        }
        return success ? "success" : "failed"
    }
}
