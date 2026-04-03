import Foundation

// MCPDispatch.swift — Routes all 30 MCP tool calls to their backing implementations.
//
// Tool coverage is enforced by two guards:
//   scripts/mcp_boundary_guard.py      – CI shell check
//   Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift – Swift unit test
//
// Architecture note: dispatch() is synchronous and runs on @MainActor.
// oracle_experiment_search is the sole exception: it is handed to an async
// handler because ExperimentManager.run() is async throws.

@MainActor
public enum MCPDispatch {
    private static let toolTimeoutSeconds: TimeInterval = 60
    private static var _bootstrappedRuntime: BootstrappedRuntime?

    private static func getBootstrappedRuntime() async throws -> BootstrappedRuntime {
        if let existing = _bootstrappedRuntime { return existing }
        let built = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .live())
        _bootstrappedRuntime = built
        return built
    }

    // MARK: - Public entry points

    public static func handle(_ params: [String: Any]) async -> [String: Any] {
        guard let request = MCPToolRequest.decode(from: params) else {
            return ["content": [["type": "text", "text": "{\"success\":false}"]], "isError": true]
        }
        return await handle(request).toLegacyDict()
    }

    public static func handle(_ request: MCPToolRequest) async -> MCPToolResponse {
        do {
            let bootstrapped = try await getBootstrappedRuntime()
            bootstrapped.container.memoryStore.setWorkspaceRoot(FileManager.default.currentDirectoryPath)
        } catch { return .error("Bootstrap failed") }

        let toolName = request.name
        let actualTimeout = toolName == "oracle_experiment_search" ? 600.0 : toolTimeoutSeconds

        struct RespWrapper: @unchecked Sendable { let payload: MCPToolResponse? }
        let response: RespWrapper
        do {
            response = try await withThrowingTaskGroup(of: RespWrapper.self) { group in
                group.addTask { @Sendable in
                    let result: MCPToolResponse
                    if toolName == "oracle_screenshot" {
                        result = await MainActor.run { handleScreenshot(request) }
                    } else if toolName == "oracle_experiment_search" {
                        result = await handleExperimentSearch(request)
                    } else {
                        result = await MainActor.run {
                            formatTypedResult(dispatch(request: request), toolName: toolName)
                        }
                    }
                    return RespWrapper(payload: result)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(actualTimeout * 1_000_000_000))
                    return RespWrapper(payload: nil)
                }
                return try await group.next() ?? RespWrapper(payload: nil)
            }
        } catch { response = RespWrapper(payload: nil) }

        return response.payload ?? .error("Timeout")
    }

    // MARK: - Special handlers

    private static func handleScreenshot(_ request: MCPToolRequest) -> MCPToolResponse {
        let res = AXScanner.screenshot(appName: request.string("app"), fullResolution: request.bool("full_resolution") ?? false)
        guard res.success, let data = res.data, let b64 = data["image"] as? String else {
            return formatTypedResult(res, toolName: "oracle_screenshot")
        }
        return .imageAndCaption(base64: b64, mimeType: data["mime_type"] as? String ?? "image/png", caption: "Screenshot")
    }

    private static func handleExperimentSearch(_ request: MCPToolRequest) async -> MCPToolResponse {
        guard let bootstrapped = _bootstrappedRuntime else {
            return .error("Runtime not bootstrapped")
        }
        let goalDescription = request.string("goal_description") ?? ""
        let rawCandidates = request.array("candidates") ?? []
        var patches: [CandidatePatch] = []
        for raw in rawCandidates {
            guard let obj = raw.objectValue,
                  let title = obj["title"]?.stringValue,
                  let summary = obj["summary"]?.stringValue,
                  let path = obj["workspace_relative_path"]?.stringValue,
                  let content = obj["content"]?.stringValue
            else { continue }
            patches.append(CandidatePatch(
                title: title,
                summary: summary,
                workspaceRelativePath: path,
                content: content,
                hypothesis: obj["hypothesis"]?.stringValue,
                strategyKind: obj["strategy_kind"]?.stringValue
            ))
        }
        guard !patches.isEmpty else {
            return formatTypedResult(
                ToolResult(success: false, error: "No valid candidates provided. Each candidate needs title, summary, workspace_relative_path, and content."),
                toolName: "oracle_experiment_search"
            )
        }
        let spec = ExperimentSpec(
            goalDescription: goalDescription,
            workspaceRoot: FileManager.default.currentDirectoryPath,
            candidates: patches,
            buildCommand: makeCommandSpec(request.strings("build_command"), category: .build),
            testCommand: makeCommandSpec(request.strings("test_command"), category: .test)
        )
        do {
            let results = try await bootstrapped.container.experimentManager.run(spec: spec)
            let summaries: [[String: Any]] = results.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "selected": r.selected,
                    "candidate_title": r.candidate.title,
                    "candidate_path": r.candidate.workspaceRelativePath,
                    "architecture_risk": r.architectureRiskScore,
                    "diff_summary": r.diffSummary,
                ]
                d["command_results"] = r.commandResults.map { cr -> [String: Any] in
                    ["succeeded": cr.succeeded, "exit_code": Int(cr.exitCode), "summary": cr.summary]
                }
                return d
            }
            return formatTypedResult(
                ToolResult(success: true, data: ["results": summaries, "count": results.count]),
                toolName: "oracle_experiment_search"
            )
        } catch {
            return formatTypedResult(
                ToolResult(success: false, error: "Experiment search failed: \(error)"),
                toolName: "oracle_experiment_search"
            )
        }
    }

    private static func makeCommandSpec(_ args: [String]?, category: CodeCommandCategory) -> CommandSpec? {
        guard let args, !args.isEmpty else { return nil }
        return CommandSpec(
            category: category,
            executable: args[0],
            arguments: Array(args.dropFirst()),
            workspaceRoot: FileManager.default.currentDirectoryPath,
            summary: args.joined(separator: " "),
            mutatesWorkspace: false,
            touchesNetwork: false
        )
    }

    // MARK: - Result formatting

    private static func formatTypedResult(_ result: ToolResult, toolName: String) -> MCPToolResponse {
        if let data = try? JSONSerialization.data(withJSONObject: result.toDict(), options: []),
           let jsonStr = String(data: data, encoding: .utf8) {
            return .text(jsonStr, isError: !result.success)
        }
        return .error("Format failed")
    }

    // MARK: - Synchronous dispatch (all tools except oracle_screenshot and oracle_experiment_search)

    private static func dispatch(request: MCPToolRequest) -> ToolResult {
        let tool = request.name
        let container = _bootstrappedRuntime!.container
        let runtime = _bootstrappedRuntime!.orchestrator

        switch tool {

        // MARK: Perception

        case "oracle_context":
            return AXScanner.getContext(appName: request.string("app"))

        case "oracle_state":
            return AXScanner.getState(appName: request.string("app"))

        case "oracle_find":
            return AXScanner.findElements(
                query: request.string("query"),
                role: request.string("role"),
                domId: nil,
                domClass: nil,
                identifier: nil,
                appName: request.string("app"),
                depth: nil
            )

        case "oracle_read":
            return AXScanner.readContent(
                appName: request.string("app"),
                query: request.string("query"),
                depth: nil
            )

        case "oracle_inspect":
            return AXScanner.inspect(
                query: request.string("query") ?? "",
                role: request.string("role"),
                domId: request.string("dom_id"),
                appName: request.string("app")
            )

        case "oracle_element_at":
            guard let x = request.double("x"), let y = request.double("y") else {
                return ToolResult(success: false, error: "x and y are required for oracle_element_at")
            }
            return AXScanner.elementAt(x: x, y: y)

        // MARK: Actions

        case "oracle_click":
            return FocusManager.withFocusRestore {
                Actions.click(
                    query: request.string("query"),
                    role: request.string("role"),
                    domId: nil,
                    appName: request.string("app"),
                    x: request.double("x"),
                    y: request.double("y"),
                    button: nil,
                    count: nil,
                    runtime: runtime,
                    surface: .mcp,
                    toolName: tool
                )
            }

        case "oracle_type":
            return FocusManager.withFocusRestore {
                Actions.typeText(
                    text: request.string("text") ?? "",
                    into: request.string("into"),
                    domId: nil,
                    appName: request.string("app"),
                    clear: request.bool("clear") ?? false,
                    runtime: runtime,
                    surface: .mcp,
                    toolName: tool
                )
            }

        case "oracle_press":
            guard let key = request.string("key") else {
                return ToolResult(success: false, error: "key is required for oracle_press")
            }
            return Actions.pressKey(
                key: key,
                modifiers: request.strings("modifiers"),
                appName: request.string("app"),
                runtime: runtime
            )

        case "oracle_hotkey":
            guard let keys = request.strings("keys"), !keys.isEmpty else {
                return ToolResult(success: false, error: "keys array is required for oracle_hotkey")
            }
            return Actions.hotkey(keys: keys, appName: request.string("app"), runtime: runtime)

        case "oracle_scroll":
            guard let direction = request.string("direction") else {
                return ToolResult(success: false, error: "direction is required for oracle_scroll")
            }
            return Actions.scroll(
                direction: direction,
                amount: request.int("amount"),
                appName: request.string("app"),
                x: request.double("x"),
                y: request.double("y"),
                runtime: runtime
            )

        case "oracle_focus":
            guard let appName = request.string("app") else {
                return ToolResult(success: false, error: "app is required for oracle_focus")
            }
            return Actions.focusApp(
                appName: appName,
                windowTitle: request.string("window"),
                runtime: runtime
            )

        case "oracle_window":
            guard let action = request.string("action"), let appName = request.string("app") else {
                return ToolResult(success: false, error: "action and app are required for oracle_window")
            }
            return Actions.manageWindow(
                action: action,
                appName: appName,
                windowTitle: request.string("window"),
                x: request.double("x"),
                y: request.double("y"),
                width: request.double("width"),
                height: request.double("height"),
                runtime: runtime
            )

        // MARK: Wait

        case "oracle_wait":
            return WaitManager.waitFor(
                condition: request.string("condition") ?? "",
                value: request.string("value"),
                appName: request.string("app"),
                timeout: request.double("timeout") ?? 10,
                interval: request.double("interval") ?? 0.5
            )

        // MARK: Vision

        case "oracle_parse_screen":
            return VisionScanner.parseScreen(
                appName: request.string("app"),
                fullResolution: request.bool("full_resolution") ?? false
            )

        case "oracle_ground":
            guard let description = request.string("description") else {
                return ToolResult(success: false, error: "description is required for oracle_ground")
            }
            let cropBox = request.array("crop_box")?.compactMap { $0.doubleValue }
            return VisionScanner.groundElement(
                description: description,
                appName: request.string("app"),
                cropBox: cropBox?.isEmpty == false ? cropBox : nil
            )

        // MARK: Recipes

        case "oracle_recipes", "oracle_run", "oracle_recipe_show", "oracle_recipe_save", "oracle_recipe_delete":
            return dispatchRecipes(request, runtime: runtime)

        // MARK: Project Memory

        case "oracle_memory_query", "oracle_memory_draft":
            return dispatchMemory(request, container: container)

        // MARK: Architecture

        case "oracle_architecture_review", "oracle_candidate_review":
            return dispatchArchitecture(request, container: container)

        // MARK: Workflows

        case "oracle_workflow_list", "oracle_workflow_mine", "oracle_workflow_execute":
            return dispatchWorkflow(request, container: container)

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }
}
