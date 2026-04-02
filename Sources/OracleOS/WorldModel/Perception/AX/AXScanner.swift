// AXScanner.swift - All perception functions for Oracle OS v2
//
// Maps to MCP tools: oracle_context, oracle_state, oracle_find, oracle_read,
// oracle_inspect, oracle_element_at, oracle_screenshot
//
// Uses AXorcist's Element, Locator, and command system directly.
// Custom code only for semantic depth tunneling (oracle_read).

import AppKit
import AXorcist
import Foundation

/// Perception engine: reading the screen state for the agent.
///
/// Formerly `Perception`. Renamed to `AXScanner` to align with
/// the canonical perception pipeline:
///   environment → perception → semantic state → planner
@MainActor
public enum AXScanner {

    /// Set a per-element AX messaging timeout before deep tree walks.
    /// Chrome/Electron apps can hang on AX calls for specific elements.
    /// Call this on the app Element before any recursive search.
    private static func setElementTimeout(_ element: Element, seconds: Float = 3.0) {
        element.setMessagingTimeout(seconds)
    }

    /// Reset element timeout to the global default (0 = use global timeout).
    private static func resetElementTimeout(_ element: Element) {
        element.setMessagingTimeout(0)
    }

    // MARK: - oracle_context

    /// Get orientation context: focused app, window, URL, focused element, visible interactive elements.

    // MARK: - Per-element timeout (internal so extension files can call it)

    static func setElementTimeout(_ element: Element, seconds: Float = 3.0) {
        element.setMessagingTimeout(seconds)
    }

    static func resetElementTimeout(_ element: Element) {
        element.setMessagingTimeout(0)
    }
}
