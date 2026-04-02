// AXScanner.swift — Perception engine facade.
//
// Maps to MCP tools: oracle_context, oracle_state, oracle_find, oracle_read,
// oracle_inspect, oracle_element_at, oracle_screenshot
//
// Uses AXorcist's Element, Locator, and command system directly.
// All logic lives in AXScanner+{Shared,Context,Find,Read,Inspect,Screenshot}.swift

import AppKit
import AXorcist
import Foundation

/// Perception engine: reading live screen state for the Oracle agent.
/// Pipeline: environment → AXScanner → semantic state → planner
@MainActor
public enum AXScanner {

    // MARK: - Per-element AX timeout helpers (internal — used by extension files)

    /// Set a per-element AX messaging timeout before deep tree walks.
    /// Chrome/Electron apps can hang; call before any recursive AX search.
    static func setElementTimeout(_ element: Element, seconds: Float = 3.0) {
        element.setMessagingTimeout(seconds)
    }

    /// Reset element timeout to the global default (0 = use global timeout).
    static func resetElementTimeout(_ element: Element) {
        element.setMessagingTimeout(0)
    }
}
