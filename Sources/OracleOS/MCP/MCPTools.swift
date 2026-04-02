// MCPTools.swift - MCP tool definitions (names, descriptions, parameter schemas)
//
// All 30 tools defined here. Agent sees these descriptions and schemas.
// Make them excellent - they're the contract between Oracle OS and the agent.

import Foundation

/// Tool definitions for the MCP server.
public enum MCPTools {

    /// All tool definitions as MCP-compatible dictionaries.
    @MainActor
    public static func definitions() -> [[String: Any]] {
        perception + actions + wait + recipes + vision + projectMemory + experiments + architecture + workflows
    }

    // MARK: - Perception Tools (7)

    @MainActor
    private static let perception: [[String: Any]] = [
        tool(
            name: "oracle_context",
            description: "Get orientation for an app. Returns summary fields plus a canonical fused observation snapshot with element source and confidence metadata. Call this before acting on any app.",
            properties: [
                "app": prop("string", "App name to get context for. If omitted, returns focused app."),
            ]
        ),
        tool(
            name: "oracle_state",
            description: "List all running apps and their windows with titles, positions, and sizes.",
            properties: [
                "app": prop("string", "Filter to a specific app."),
            ]
        ),
        tool(
            name: "oracle_find",
            description: "Find elements in any app. Returns matching elements with role, name, position, and available actions.",
            properties: [
                "query": prop("string", "Text to search for (matches title, value, identifier, description)."),
                "role": prop("string", "AX role filter (e.g. AXButton, AXTextField, AXLink)."),
                "dom_id": prop("string", "Find by DOM id (web apps, bypasses depth limits)."),
                "dom_class": prop("string", "Find by CSS class."),
                "identifier": prop("string", "Find by AX identifier."),
                "app": prop("string", "Which app to search in."),
                "depth": prop("integer", "Max search depth (default: 25, max: 100)."),
            ]
        ),
        tool(
            name: "oracle_read",
            description: "Read text content from screen. Returns concatenated text from the element subtree.",
            properties: [
                "app": prop("string", "Which app to read from."),
                "query": prop("string", "Narrow to specific element."),
                "depth": prop("integer", "How deep to read (default: 25)."),
            ]
        ),
        tool(
            name: "oracle_inspect",
            description: "Full metadata about one element. Call this before acting on something you're unsure about. Returns role, title, position, size, actionable status, supported actions, editable, DOM id, and more.",
            properties: [
                "query": prop("string", "Element to inspect."),
                "role": prop("string", "AX role filter."),
                "dom_id": prop("string", "Find by DOM id."),
                "app": prop("string", "Which app."),
            ],
            required: ["query"]
        ),
        tool(
            name: "oracle_element_at",
            description: "What element is at this screen position? Bridges screenshots and accessibility tree.",
            properties: [
                "x": prop("number", "X coordinate."),
                "y": prop("number", "Y coordinate."),
            ],
            required: ["x", "y"]
        ),
        tool(
            name: "oracle_screenshot",
            description: "Take a screenshot for visual debugging. Returns base64 PNG.",
            properties: [
                "app": prop("string", "Screenshot specific app window."),
                "full_resolution": prop("boolean", "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
    ]

    // MARK: - Action Tools (7)

    @MainActor
    private static let actions: [[String: Any]] = [
        tool(
            name: "oracle_click",
            description: "Click an element. Tries AX-native first, falls back to synthetic click. Risky actions may return pending approval instead of executing immediately.",
            properties: [
                "query": prop("string", "What to click (element text/name)."),
                "role": prop("string", "AX role filter."),
                "dom_id": prop("string", "Click by DOM id."),
                "app": prop("string", "Which app (auto-focuses if needed)."),
                "x": prop("number", "Click at X coordinate instead of element."),
                "y": prop("number", "Click at Y coordinate."),
                "button": prop("string", "left (default), right, or middle."),
                "count": prop("integer", "Click count: 1=single, 2=double, 3=triple."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ]
        ),
        tool(
            name: "oracle_type",
            description: "Type text into a field. If 'into' is specified, finds the field first. Risky text entry may require approval before execution.",
            properties: [
                "text": prop("string", "Text to type."),
                "into": prop("string", "Target field name (finds via accessibility). If omitted, types at focus."),
                "dom_id": prop("string", "Target field by DOM id."),
                "app": prop("string", "Which app."),
                "clear": prop("boolean", "Clear field before typing (default: false)."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["text"]
        ),
        tool(
            name: "oracle_press",
            description: "Press a single key. When app is provided, Oracle verifies the target app is frontmost after dispatch.",
            properties: [
                "key": prop("string", "Key name: return, tab, escape, space, delete, up, down, left, right, f1-f12."),
                "modifiers": propArray("string", "Modifier keys: cmd, shift, option, control."),
                "app": prop("string", "Auto-focus this app first (IMPORTANT for synthetic input)."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["key"]
        ),
        tool(
            name: "oracle_hotkey",
            description: "Press a key combination. Modifier keys are auto-cleared afterward. Always include app parameter.",
            properties: [
                "keys": propArray("string", "Key combo, e.g. [\"cmd\", \"return\"] or [\"cmd\", \"shift\", \"p\"]."),
                "app": prop("string", "Auto-focus this app first (IMPORTANT for synthetic input)."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["keys"]
        ),
        tool(
            name: "oracle_scroll",
            description: "Scroll content in a direction.",
            properties: [
                "direction": prop("string", "up, down, left, or right."),
                "amount": prop("integer", "Scroll amount in lines (default: 3)."),
                "app": prop("string", "Auto-focus this app first."),
                "x": prop("number", "Scroll at specific X position."),
                "y": prop("number", "Scroll at specific Y position."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["direction"]
        ),
        tool(
            name: "oracle_focus",
            description: "Bring an app or window to the front. Returns verified success when the requested app becomes frontmost.",
            properties: [
                "app": prop("string", "App name to focus."),
                "window": prop("string", "Window title substring to focus specific window."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["app"]
        ),
        tool(
            name: "oracle_window",
            description: "Window management: minimize, maximize, close, restore, move, resize, or list windows.",
            properties: [
                "action": prop("string", "minimize, maximize, close, restore, move, resize, or list."),
                "app": prop("string", "Target app."),
                "window": prop("string", "Window title (if omitted, acts on frontmost window of app)."),
                "x": prop("number", "X position for move."),
                "y": prop("number", "Y position for move."),
                "width": prop("number", "Width for resize."),
                "height": prop("number", "Height for resize."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["action", "app"]
        ),
    ]

    // MARK: - Wait Tool (1)

    @MainActor
    private static let wait: [[String: Any]] = [
        tool(
            name: "oracle_wait",
            description: "Wait for a condition instead of using fixed delays. Polls until condition is met or timeout.",
            properties: [
                "condition": prop("string", "appFrontmost, urlContains, windowTitleContains, titleContains, elementExists, elementGone, urlChanged, titleChanged, focusEquals, valueEquals."),
                "value": prop("string", "Match value. For focusEquals, this is the focused element label/query. For valueEquals, this is the focused element value."),
                "timeout": prop("number", "Max seconds to wait (default: 10)."),
                "interval": prop("number", "Poll interval in seconds (default: 0.5)."),
                "app": prop("string", "App to check against."),
            ],
            required: ["condition"]
        ),
    ]

    // MARK: - Recipe Tools (5)

    @MainActor
    private static let recipes: [[String: Any]] = [
        tool(
            name: "oracle_recipes",
            description: "List all installed recipes with descriptions and parameters. ALWAYS check this first before doing multi-step tasks manually.",
            properties: [:]
        ),
        tool(
            name: "oracle_run",
            description: "Execute a recipe with parameter substitution. Risky steps pause for approval and can be resumed with resume_token plus approval_request_id.",
            properties: [
                "recipe": prop("string", "Recipe name."),
                "params": prop("object", "Parameter values for substitution."),
                "resume_token": prop("string", "Resume a previously paused recipe run."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a gated recipe step."),
            ],
            required: []
        ),
        tool(
            name: "oracle_recipe_show",
            description: "View full recipe details: steps, parameters, preconditions.",
            properties: [
                "name": prop("string", "Recipe name."),
            ],
            required: ["name"]
        ),
        tool(
            name: "oracle_recipe_save",
            description: "Install a new recipe from JSON.",
            properties: [
                "recipe_json": prop("string", "Complete recipe JSON string."),
            ],
            required: ["recipe_json"]
        ),
        tool(
            name: "oracle_recipe_delete",
            description: "Delete a recipe.",
            properties: [
                "name": prop("string", "Recipe name to delete."),
            ],
            required: ["name"]
        ),
    ]

    // MARK: - Vision Tools (2)

    @MainActor
    private static let vision: [[String: Any]] = [
        tool(
            name: "oracle_parse_screen",
            description: "Experimental full-screen vision parsing via the sidecar. The tool is available, but its schema and reliability are still being hardened. Prefer oracle_find for stable AX queries and oracle_ground for precise visual grounding.",
            properties: [
                "app": prop("string", "Screenshot specific app window."),
                "full_resolution": prop("boolean", "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
        tool(
            name: "oracle_ground",
            description: "Find precise screen coordinates for a described UI element using vision (VLM). Use when oracle_find can't locate the element or returns AXGroup elements. Pass a text description of what to click. Requires the vision sidecar to be running.",
            properties: [
                "description": prop("string", "What to find (e.g. 'Compose button', 'Send button', 'search field')."),
                "app": prop("string", "Screenshot specific app window."),
                "crop_box": propArray("number", "Optional crop region [x1, y1, x2, y2] in logical points. Dramatically improves accuracy for overlapping panels (e.g. compose popup over inbox)."),
            ],
            required: ["description"]
        ),
    ]

    // MARK: - Project Memory Tools (2)

    @MainActor
    private static let projectMemory: [[String: Any]] = [
        tool(
            name: "oracle_memory_query",
            description: "Query the project memory store for past architecture decisions, known patterns, open problems, and risks.",
            properties: [
                "query": prop("string", "Text to search for. If empty, returns recent records."),
                "modules": propArray("string", "Optional list of affected module names to filter by."),
                "kinds": propArray("string", "Optional list of memory kinds to filter by: architecture-decision, open-problem, rejected-approach, known-good-pattern, risk."),
                "limit": prop("integer", "Max results to return (default: 10).")
            ],
            required: []
        ),
        tool(
            name: "oracle_memory_draft",
            description: "Draft a new project memory record to persist organizational knowledge like architecture decisions, known safe patterns, risks, open problems, or rejected approaches.",
            properties: [
                "title": prop("string", "Short, concise title of the memory."),
                "summary": prop("string", "A very short, 1-2 sentence summary of the context and outcome."),
                "kind": prop("string", "Must be one of: architecture-decision, open-problem, rejected-approach, known-good-pattern, risk."),
                "body": prop("string", "The detailed Markdown body explaining context, options, consequences, and actual implementation details."),
                "affected_modules": propArray("string", "Optional list of modules this memory applies to."),
                "evidence_refs": propArray("string", "Optional list of related files, commit SHAs, or ticket numbers for reference.")
            ],
            required: ["title", "summary", "kind", "body"]
        ),
    ]

    // MARK: - Experiment Tools (1)

    @MainActor
    private static let experiments: [[String: Any]] = [
        tool(
            name: "oracle_experiment_search",
            description: "Run a bounded parallel experiment search. Evaluates multiple candidate file patches in isolated worktrees concurrently to find a working solution. Returns the ranking and test outputs of each candidate.",
            properties: [
                "goal_description": prop("string", "A summary of what the patches are trying to achieve."),
                "candidates": propArray("object", "List of candidates. Each must be an object with 'title', 'summary', 'workspace_relative_path', and 'content' (the complete new file string). Optional 'hypothesis' and 'strategy_kind'."),
                "build_command": propArray("string", "Optional explicit build command array (e.g. ['swift', 'build']). If omitted, auto-detected."),
                "test_command": propArray("string", "Optional explicit test command array (e.g. ['swift', 'test']). If omitted, auto-detected.")
            ],
            required: ["goal_description", "candidates"]
        ),
    ]

    // MARK: - Architecture Tools (2)

    @MainActor
    private static let architecture: [[String: Any]] = [
        tool(
            name: "oracle_architecture_review",
            description: "Review planned changes for architectural risks and potential invariant violations before executing them. Returns structured findings, risk scores, and refactoring proposals.",
            properties: [
                "goal_description": prop("string", "A summary of what the change is trying to achieve."),
                "candidate_paths": propArray("string", "List of workspace relative paths that are expected to be changed."),
            ],
            required: ["goal_description", "candidate_paths"]
        ),
        tool(
            name: "oracle_candidate_review",
            description: "Deep architecture review of a specific code patch candidate. Identifies heuristic problems like touching wrong boundaries or expanding patch radii.",
            properties: [
                "goal_description": prop("string", "A summary of what the patch is trying to achieve."),
                "candidate": prop("object", "Candidate patch object with 'title', 'summary', 'workspace_relative_path', and 'content' (the complete new file string)."),
                "diff_summary": prop("string", "A short diff format summary of the change.")
            ],
            required: ["goal_description", "candidate", "diff_summary"]
        )
    ]

    // MARK: - Workflow Tools (3)

    @MainActor
    private static let workflows: [[String: Any]] = [
        tool(
            name: "oracle_workflow_mine",
            description: "Synthesize reusable workflows by mining recent telemetry and traces. Extracts generalized patterns of success.",
            properties: [
                "goal_pattern": prop("string", "The goal or pattern to search for in traces."),
                "limit": prop("integer", "Maximum number of recent events to analyze (default: 1000).")
            ],
            required: ["goal_pattern"]
        ),
        tool(
            name: "oracle_workflow_list",
            description: "List all known synthesized workflows available in the index.",
            properties: [:],
            required: []
        ),
        tool(
            name: "oracle_workflow_execute",
            description: "Execute a synthesized workflow by its ID using the specified parameters.",
            properties: [
                "workflow_id": prop("string", "The ID of the workflow to execute."),
                "parameters": prop("object", "Parameter substitutions for the workflow slots.")
            ],
            required: ["workflow_id"]
        )
    ]

    // MARK: - Schema Helpers

    private static func tool(
        name: String,
        description: String,
        properties: [String: [String: Any]],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema,
        ]
    }

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func propArray(_ itemType: String, _ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": itemType], "description": description]
    }
}
