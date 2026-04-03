// Actions.swift — Shared infrastructure for oracle action tools.
//
// This file is intentionally thin. Action implementations live in
// per-family extension files:
//   Actions+Click.swift   — oracle_click
//   Actions+Type.swift    — oracle_type
//   Actions+Key.swift     — oracle_press, oracle_hotkey, oracle_focus
//   Actions+Scroll.swift  — oracle_scroll
//   Actions+Window.swift  — oracle_window
//   Actions+Helpers.swift — shared internal helpers (finders, postconditions)
//
// The Action Loop (every action follows this):
// 1. PRE-FLIGHT: find element via AXorcist, check actionable
// 2. EXECUTE: AX-native first, synthetic fallback if no state change
// 3. POST-VERIFY: brief pause, read post-action context
// 4. CLEANUP: clear modifier flags, restore focus

import AppKit
import AXorcist
import Foundation

/// Errors that can occur during action execution
public enum ActionError: Error, Sendable {
    case invalidParameter(String)
    case elementNotFound(String)
    case actionFailed(String)
}

// MARK: - Safe Parameter Extraction (file-private, used by legacy callers)

private func extractString(_ params: [String: Any], _ key: String) -> String? {
    params[key] as? String
}

private func extractInt(_ params: [String: Any], _ key: String) -> Int? {
    if let i = params[key] as? Int { return i }
    if let d = params[key] as? Double { return Int(d) }
    if let s = params[key] as? String, let i = Int(s) { return i }
    return nil
}

private func extractDouble(_ params: [String: Any], _ key: String) -> Double? {
    if let d = params[key] as? Double { return d }
    if let i = params[key] as? Int { return Double(i) }
    if let s = params[key] as? String, let d = Double(s) { return d }
    return nil
}

private func extractBool(_ params: [String: Any], _ key: String) -> Bool? {
    params[key] as? Bool
}

/// Actions module: operating apps for the agent.
///
/// Note: This module uses `Thread.sleep(forTimeInterval:)` for timing-critical UI waits.
/// These are intentionally kept short (50-300ms) to balance responsiveness with reliability.
/// In a @MainActor context, these block the thread, but they are necessary for waiting
/// for UI state changes to propagate.
@MainActor
public enum Actions {
    // MARK: - Runtime routing (internal so extension files can call it)

    static func plannerFamily(for agentKind: AgentKind) -> PlannerFamily {
        switch agentKind {
        case .os: .os
        case .code: .code
        }
    }

    static func stepPhase(for agentKind: AgentKind) -> TaskStepPhase {
        switch agentKind {
        case .code: .engineering
        case .os: .operatingSystem
        }
    }

    static func executeThroughRuntime(
        runtime: RuntimeOrchestrator,
        surface: RuntimeSurface,
        actionIntent: @autoclosure () -> ActionIntent,
        approvalToken: String? = nil
    ) -> ToolResult {
        let intent = actionIntent()
        let family = plannerFamily(for: intent.agentKind)
        let actionContract = ActionContract.from(
            intent: intent,
            method: "intent-api-forwarder",
            selectedElementLabel: intent.targetQuery,
            plannerFamily: family.rawValue
        )
        let plannerDecision = PlannerDecision(
            agentKind: intent.agentKind,
            plannerFamily: family,
            stepPhase: stepPhase(for: intent.agentKind),
            actionContract: actionContract,
            source: .strategy,
            notes: ["actions.intent-api-forwarder", "surface=\(surface.rawValue)"]
        )
        let driver = RuntimeExecutionDriver(intentAPI: runtime, surface: surface)
        return driver.execute(
            intent: intent,
            plannerDecision: plannerDecision,
            selectedCandidate: nil,
            approvalToken: approvalToken
        )
    }
}

