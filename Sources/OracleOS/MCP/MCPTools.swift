// MCPTools.swift - MCP tool definitions (names, descriptions, parameter schemas)
//
// All 30 tools defined here. Agent sees these descriptions and schemas.
// Make them excellent - they're the contract between Oracle OS and the agent.

import Foundation

/// Typed constants for every MCP tool name.
/// Both MCPTools (schema definitions) and MCPDispatch (routing) reference these
/// constants so a rename is a compile error, not a silent dispatch miss.
public enum MCPToolName {
    public static let context            = "oracle_context"
    public static let state              = "oracle_state"
    public static let find               = "oracle_find"
    public static let read               = "oracle_read"
    public static let inspect            = "oracle_inspect"
    public static let elementAt          = "oracle_element_at"
    public static let screenshot         = "oracle_screenshot"
    public static let click              = "oracle_click"
    public static let type_              = "oracle_type"
    public static let press              = "oracle_press"
    public static let hotkey             = "oracle_hotkey"
    public static let scroll             = "oracle_scroll"
    public static let focus              = "oracle_focus"
    public static let window             = "oracle_window"
    public static let wait               = "oracle_wait"
    public static let recipes            = "oracle_recipes"
    public static let run                = "oracle_run"
    public static let recipeShow         = "oracle_recipe_show"
    public static let recipeSave         = "oracle_recipe_save"
    public static let recipeDelete       = "oracle_recipe_delete"
    public static let parseScreen        = "oracle_parse_screen"
    public static let ground             = "oracle_ground"
    public static let memoryQuery        = "oracle_memory_query"
    public static let memoryDraft        = "oracle_memory_draft"
    public static let experimentSearch   = "oracle_experiment_search"
    public static let architectureReview = "oracle_architecture_review"
    public static let candidateReview    = "oracle_candidate_review"
    public static let workflowMine       = "oracle_workflow_mine"
    public static let workflowList       = "oracle_workflow_list"
    public static let workflowExecute    = "oracle_workflow_execute"
}

public struct MCPToolDefinition: Encodable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPToolInputSchema

    public init(name: String, description: String, inputSchema: MCPToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolInputSchema: Encodable, Sendable {
    public let type: String
    public let properties: [String: MCPPropertySchema]
    public let required: [String]?

    public init(
        type: String = "object",
        properties: [String: MCPPropertySchema],
        required: [String]? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct MCPPropertySchema: Encodable, Sendable {
    public let type: String
    public let description: String
    public let items: MCPPropertyItemsSchema?

    public init(type: String, description: String, items: MCPPropertyItemsSchema? = nil) {
        self.type = type
        self.description = description
        self.items = items
    }
}

public struct MCPPropertyItemsSchema: Encodable, Sendable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

/// Tool definitions for the MCP server.
public enum MCPTools {

    /// All tool definitions as MCP-compatible dictionaries.
    @MainActor
    public static func definitions() -> [[String: Any]] {
        allDefinitions.map { definition in
            guard let legacyDictionary = definition.legacyDictionary else {
                preconditionFailure(
                    "Failed to encode MCP tool definition '\(definition.name)' to legacy dictionary. Refusing to return a partial MCP tools list."
                )
            }
            return legacyDictionary
        }
    }

    @MainActor
    private static var allDefinitions: [MCPToolDefinition] {
        perception + actions + wait + recipes + vision + projectMemory + experiments + architecture + workflows
    }

    // MARK: - Perception Tools (7)

    @MainActor
    private static let perception: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.context,
            description: "Get orientation for an app. Returns summary fields plus a canonical fused observation snapshot with element source and confidence metadata. Call this before acting on any app.",
            properties: [
                "app": prop("string", "App name to get context for. If omitted, returns focused app."),
            ]
        ),
        tool(
            name: MCPToolName.state,
            description: "List all running apps and their windows with titles, positions, and sizes.",
            properties: [
                "app": prop("string", "Filter to a specific app."),
            ]
        ),
        tool(
            name: MCPToolName.find,
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
            name: MCPToolName.read,
            description: "Read text content from screen. Returns concatenated text from the element subtree.",
            properties: [
                "app": prop("string", "Which app to read from."),
                "query": prop("string", "Narrow to specific element."),
                "depth": prop("integer", "How deep to read (default: 25)."),
            ]
        ),
        tool(
            name: MCPToolName.inspect,
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
            name: MCPToolName.elementAt,
            description: "What element is at this screen position? Bridges screenshots and accessibility tree.",
            properties: [
                "x": prop("number", "X coordinate."),
                "y": prop("number", "Y coordinate."),
            ],
            required: ["x", "y"]
        ),
        tool(
            name: MCPToolName.screenshot,
            description: "Take a screenshot for visual debugging. Returns base64 PNG.",
            properties: [
                "app": prop("string", "Screenshot specific app window."),
                "full_resolution": prop("boolean", "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
    ]

    // MARK: - Action Tools (7)

    @MainActor
    private static let actions: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.click,
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
            name: MCPToolName.type_,
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
            name: MCPToolName.press,
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
            name: MCPToolName.hotkey,
            description: "Press a key combination. Modifier keys are auto-cleared afterward. Always include app parameter.",
            properties: [
                "keys": propArray("string", "Key combo, e.g. [\"cmd\", \"return\"] or [\"cmd\", \"shift\", \"p\"]."),
                "app": prop("string", "Auto-focus this app first (IMPORTANT for synthetic input)."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["keys"]
        ),
        tool(
            name: MCPToolName.scroll,
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
            name: MCPToolName.focus,
            description: "Bring an app or window to the front. Returns verified success when the requested app becomes frontmost.",
            properties: [
                "app": prop("string", "App name to focus."),
                "window": prop("string", "Window title substring to focus specific window."),
                "approval_request_id": prop("string", "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["app"]
        ),
        tool(
            name: MCPToolName.window,
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
    private static let wait: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.wait,
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
    private static let recipes: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.recipes,
            description: "List all installed recipes with descriptions and parameters. ALWAYS check this first before doing multi-step tasks manually.",
            properties: [:]
        ),
        tool(
            name: MCPToolName.run,
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
            name: MCPToolName.recipeShow,
            description: "View full recipe details: steps, parameters, preconditions.",
            properties: [
                "name": prop("string", "Recipe name."),
            ],
            required: ["name"]
        ),
        tool(
            name: MCPToolName.recipeSave,
            description: "Install a new recipe from JSON.",
            properties: [
                "recipe_json": prop("string", "Complete recipe JSON string."),
            ],
            required: ["recipe_json"]
        ),
        tool(
            name: MCPToolName.recipeDelete,
            description: "Delete a recipe.",
            properties: [
                "name": prop("string", "Recipe name to delete."),
            ],
            required: ["name"]
        ),
    ]

    // MARK: - Vision Tools (2)

    @MainActor
    private static let vision: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.parseScreen,
            description: "Experimental full-screen vision parsing via the sidecar. The tool is available, but its schema and reliability are still being hardened. Prefer oracle_find for stable AX queries and oracle_ground for precise visual grounding.",
            properties: [
                "app": prop("string", "Screenshot specific app window."),
                "full_resolution": prop("boolean", "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
        tool(
            name: MCPToolName.ground,
            description: "Optional experimental visual grounding via the vision sidecar. Finds precise screen coordinates for a described UI element using vision (VLM). Use when oracle_find can't locate the element or returns AXGroup elements. Pass a text description of what to click.",
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
    private static let projectMemory: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.memoryQuery,
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
            name: MCPToolName.memoryDraft,
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
    private static let experiments: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.experimentSearch,
            description: "Run a bounded parallel experiment search. Evaluates multiple candidate file patches in isolated worktrees and returns advisory rankings plus build or test summaries for each candidate. Results are sandbox-only and do not commit to the workspace.",
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
    private static let architecture: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.architectureReview,
            description: "Advisory review of planned changes for architectural risks and potential invariant violations before executing them. Returns structured findings, heuristic risk scores, and refactoring suggestions.",
            properties: [
                "goal_description": prop("string", "A summary of what the change is trying to achieve."),
                "candidate_paths": propArray("string", "List of workspace relative paths that are expected to be changed."),
            ],
            required: ["goal_description", "candidate_paths"]
        ),
        tool(
            name: MCPToolName.candidateReview,
            description: "Advisory deep architecture review of a specific code patch candidate. Identifies heuristic problems like touching wrong boundaries or expanding patch radii.",
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
    private static let workflows: [MCPToolDefinition] = [
        tool(
            name: MCPToolName.workflowMine,
            description: "Mine candidate workflows from recent telemetry and traces. Returns synthesized workflow suggestions that still require caller review before reuse or promotion.",
            properties: [
                "goal_pattern": prop("string", "The goal or pattern to search for in traces."),
                "limit": prop("integer", "Maximum number of recent events to analyze (default: 1000).")
            ],
            required: ["goal_pattern"]
        ),
        tool(
            name: MCPToolName.workflowList,
            description: "List all known synthesized workflows available in the index.",
            properties: [:],
            required: []
        ),
        tool(
            name: MCPToolName.workflowExecute,
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
        properties: [String: MCPPropertySchema],
        required: [String] = []
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: name,
            description: description,
            inputSchema: MCPToolInputSchema(
                properties: properties,
                required: required.isEmpty ? nil : required
            )
        )
    }

    private static func prop(_ type: String, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(type: type, description: description)
    }

    private static func propArray(_ itemType: String, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(
            type: "array",
            items: MCPPropertySchema(type: itemType),
            description: description
        )
    }

    private static func prop(_ type: String, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(type: type, description: description)
    }
}

struct MCPToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: MCPToolInputSchema

    var legacyDictionary: [String: Any]? {
        MCPDispatch.legacyDict(for: self)
    }
}

struct MCPToolInputSchema: Encodable {
    let type = "object"
    let properties: [String: MCPPropertySchema]
    let required: [String]?
}

struct MCPPropertySchema: Encodable {
    let type: String
    let items: MCPPropertySchema?
    let description: String?

    init(
        type: String,
        items: MCPPropertySchema? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.items = items
        self.description = description
    private static func propArray(_ itemType: String, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(type: "array", description: description, items: MCPPropertyItemsSchema(type: itemType))
    }
}
