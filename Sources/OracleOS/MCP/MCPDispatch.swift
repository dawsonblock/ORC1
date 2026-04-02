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

        case "oracle_recipes":
            let recipes = RecipeStore.listRecipes()
            let summaries: [[String: Any]] = recipes.map { r in
                var d: [String: Any] = ["name": r.name, "description": r.description]
                if let params = r.params, !params.isEmpty {
                    d["parameters"] = Array(params.keys).sorted()
                }
                return d
            }
            return ToolResult(success: true, data: ["recipes": summaries, "count": summaries.count])

        case "oracle_run":
            if let resumeToken = request.string("resume_token") {
                return RecipeEngine.resume(
                    resumeToken: resumeToken,
                    approvalRequestID: request.string("approval_request_id"),
                    runtime: runtime
                )
            }
            guard let recipeName = request.string("recipe") else {
                return ToolResult(success: false, error: "recipe is required for oracle_run")
            }
            guard let recipe = RecipeStore.loadRecipe(named: recipeName) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(recipeName)' not found",
                    suggestion: "Use oracle_recipes to list available recipes."
                )
            }
            var params: [String: String] = [:]
            if let paramsValue = request.arguments.objectValue?["params"],
               let paramsDict = paramsValue.objectValue {
                for (k, v) in paramsDict {
                    if let s = v.stringValue { params[k] = s }
                }
            }
            return RecipeEngine.run(recipe: recipe, params: params, runtime: runtime)

        case "oracle_recipe_show":
            guard let name = request.string("name") else {
                return ToolResult(success: false, error: "name is required for oracle_recipe_show")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(success: false, error: "Recipe '\(name)' not found")
            }
            let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
            guard let data = try? encoder.encode(recipe),
                  let jsonStr = String(data: data, encoding: .utf8) else {
                return ToolResult(success: false, error: "Failed to serialize recipe '\(name)'")
            }
            return ToolResult(success: true, data: ["name": name, "recipe": jsonStr])

        case "oracle_recipe_save":
            guard let jsonStr = request.string("recipe_json") else {
                return ToolResult(success: false, error: "recipe_json is required for oracle_recipe_save")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonStr)
                return ToolResult(
                    success: true,
                    data: ["saved": name],
                    suggestion: "Recipe '\(name)' saved. Use oracle_run to execute it."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case "oracle_recipe_delete":
            guard let name = request.string("name") else {
                return ToolResult(success: false, error: "name is required for oracle_recipe_delete")
            }
            let deleted = RecipeStore.deleteRecipe(named: name)
            return ToolResult(
                success: deleted,
                error: deleted ? nil : "Recipe '\(name)' not found or could not be deleted"
            )

        // MARK: Project Memory

        case "oracle_memory_query":
            guard let projectStore = container.memoryStore.projectStore else {
                return ToolResult(
                    success: false,
                    error: "Project memory not initialized. Ensure workspace root is set.",
                    suggestion: "The server needs a git workspace root to locate the ProjectMemory directory."
                )
            }
            let queryText = request.string("query") ?? ""
            let modules = request.strings("modules") ?? []
            let kindStrings = request.strings("kinds") ?? []
            let kinds = kindStrings.compactMap { ProjectMemoryKind(rawValue: $0) }
            let limit = request.int("limit") ?? 10
            let allRecords = projectStore.allRecords()
            let filtered: [ProjectMemoryRecord]
            if queryText.isEmpty && kinds.isEmpty && modules.isEmpty {
                filtered = Array(allRecords.prefix(limit))
            } else {
                filtered = Array(allRecords.filter { r in
                    let matchesQuery = queryText.isEmpty
                        || r.title.localizedCaseInsensitiveContains(queryText)
                        || r.summary.localizedCaseInsensitiveContains(queryText)
                        || r.body.localizedCaseInsensitiveContains(queryText)
                    let matchesKind = kinds.isEmpty || kinds.contains(r.kind)
                    let matchesModules = modules.isEmpty
                        || modules.contains { mod in r.affectedModules.contains(mod) }
                    return matchesQuery && matchesKind && matchesModules
                }.prefix(limit))
            }
            let serialized: [[String: Any]] = filtered.map { r in
                var d: [String: Any] = [
                    "id": r.id,
                    "kind": r.kind.rawValue,
                    "title": r.title,
                    "summary": r.summary,
                    "knowledge_class": r.knowledgeClass.rawValue,
                ]
                if !r.affectedModules.isEmpty { d["affected_modules"] = r.affectedModules }
                if !r.body.isEmpty { d["body"] = r.body }
                if !r.evidenceRefs.isEmpty { d["evidence_refs"] = r.evidenceRefs }
                return d
            }
            return ToolResult(success: true, data: ["records": serialized, "count": serialized.count])

        case "oracle_memory_draft":
            guard let title = request.string("title"),
                  let summary = request.string("summary"),
                  let kindStr = request.string("kind"),
                  let body = request.string("body") else {
                return ToolResult(
                    success: false,
                    error: "title, summary, kind, and body are all required for oracle_memory_draft"
                )
            }
            let validKinds = "architecture-decision, open-problem, rejected-approach, known-good-pattern, risk"
            guard ProjectMemoryKind(rawValue: kindStr) != nil else {
                return ToolResult(
                    success: false,
                    error: "Invalid kind '\(kindStr)'. Must be one of: \(validKinds)"
                )
            }
            let modules = request.strings("affected_modules") ?? []
            let refs = request.strings("evidence_refs") ?? []
            let memStore = container.memoryStore
            do {
                switch kindStr {
                case "architecture-decision":
                    try memStore.recordArchitectureDecision(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "open-problem":
                    try memStore.recordOpenProblem(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "rejected-approach":
                    try memStore.recordRejectedApproach(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "known-good-pattern":
                    try memStore.recordKnownGoodPattern(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                case "risk":
                    // UnifiedMemoryStore has no recordRisk wrapper; call projectStore directly.
                    guard let ps = memStore.projectStore else {
                        return ToolResult(success: false, error: "Project memory not initialized")
                    }
                    _ = try ps.writeRiskDraft(
                        title: title, summary: summary, knowledgeClass: .reusable,
                        affectedModules: modules, evidenceRefs: refs, body: body
                    )
                default:
                    return ToolResult(success: false, error: "Unhandled kind: \(kindStr)")
                }
                return ToolResult(
                    success: true,
                    data: ["drafted": title, "kind": kindStr],
                    suggestion: "Memory record '\(title)' persisted. Retrieve with oracle_memory_query."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to record memory: \(error)")
            }

        // MARK: Architecture

        case "oracle_architecture_review":
            guard let goalDescription = request.string("goal_description") else {
                return ToolResult(success: false, error: "goal_description is required for oracle_architecture_review")
            }
            let candidatePaths = request.strings("candidate_paths") ?? []
            let workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let snapshot = container.repositoryIndexer.indexIfNeeded(workspaceRoot: workspaceURL)
            let review = container.architectureEngine.review(
                goalDescription: goalDescription,
                snapshot: snapshot,
                candidatePaths: candidatePaths
            )
            return ToolResult(success: true, data: archReviewToDict(review))

        case "oracle_candidate_review":
            guard let goalDescription = request.string("goal_description"),
                  let diffSummary = request.string("diff_summary") else {
                return ToolResult(
                    success: false,
                    error: "goal_description and diff_summary are required for oracle_candidate_review"
                )
            }
            guard let candidateValue = request.arguments.objectValue?["candidate"],
                  let obj = candidateValue.objectValue,
                  let title = obj["title"]?.stringValue,
                  let patchSummary = obj["summary"]?.stringValue,
                  let path = obj["workspace_relative_path"]?.stringValue,
                  let content = obj["content"]?.stringValue else {
                return ToolResult(
                    success: false,
                    error: "candidate object with title, summary, workspace_relative_path, and content is required"
                )
            }
            let patch = CandidatePatch(
                title: title,
                summary: patchSummary,
                workspaceRelativePath: path,
                content: content
            )
            let workspaceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            let snapshot = container.repositoryIndexer.indexIfNeeded(workspaceRoot: workspaceURL)
            let review = container.architectureEngine.reviewCandidatePatch(
                goalDescription: goalDescription,
                snapshot: snapshot,
                candidate: patch,
                diffSummary: diffSummary
            )
            return ToolResult(success: true, data: archReviewToDict(review))

        // MARK: Workflows

        case "oracle_workflow_list":
            let index = WorkflowIndex()
            let plans = index.allPlans()
            let serialized: [[String: Any]] = plans.map { p in [
                "id": p.id,
                "goal_pattern": p.goalPattern,
                "success_rate": p.successRate,
                "step_count": p.steps.count,
                "parameter_slots": p.parameterSlots,
                "promotion_status": p.promotionStatus.rawValue,
            ] }
            return ToolResult(success: true, data: ["workflows": serialized, "count": serialized.count])

        case "oracle_workflow_mine":
            guard let goalPattern = request.string("goal_pattern") else {
                return ToolResult(success: false, error: "goal_pattern is required for oracle_workflow_mine")
            }
            let limit = request.int("limit") ?? 1000
            let events = container.traceStore.loadRecentEvents(limit: limit)
            let synthesized = WorkflowSynthesizer().synthesize(goalPattern: goalPattern, events: events)
            if synthesized.isEmpty {
                return ToolResult(
                    success: true,
                    data: ["synthesized": 0, "workflows": [[String: Any]]()],
                    suggestion: "No repeatable patterns found for '\(goalPattern)'. Run more successful traces to build workflow patterns."
                )
            }
            let index = WorkflowIndex()
            for plan in synthesized { index.add(plan) }
            let serialized: [[String: Any]] = synthesized.map { p in [
                "id": p.id,
                "goal_pattern": p.goalPattern,
                "success_rate": p.successRate,
                "step_count": p.steps.count,
                "parameter_slots": p.parameterSlots,
            ] }
            return ToolResult(
                success: true,
                data: ["synthesized": synthesized.count, "workflows": serialized],
                suggestion: "Synthesized \(synthesized.count) workflow(s) and saved to index. Use oracle_workflow_list to see all."
            )

        case "oracle_workflow_execute":
            guard let workflowID = request.string("workflow_id") else {
                return ToolResult(success: false, error: "workflow_id is required for oracle_workflow_execute")
            }
            let index = WorkflowIndex()
            guard let plan = index.plan(id: workflowID) else {
                return ToolResult(
                    success: false,
                    error: "Workflow '\(workflowID)' not found.",
                    suggestion: "Use oracle_workflow_list to see available workflow IDs."
                )
            }
            // WorkflowExecutor operates at the planner level and requires full PlannerFamily context.
            // Return the structured step plan so the agent can execute steps with oracle tools.
            let steps: [[String: Any]] = plan.steps.enumerated().map { idx, s in
                var d: [String: Any] = [
                    "step": idx + 1,
                    "agent_kind": s.agentKind.rawValue,
                    "skill": s.actionContract.skillName,
                    "domain": s.actionContract.domain,
                ]
                if !s.notes.isEmpty { d["notes"] = s.notes }
                if let q = s.semanticQuery?.text { d["query"] = q }
                return d
            }
            return ToolResult(
                success: true,
                data: [
                    "workflow_id": plan.id,
                    "goal_pattern": plan.goalPattern,
                    "step_count": plan.steps.count,
                    "parameter_slots": plan.parameterSlots,
                    "steps": steps,
                ],
                suggestion: "Follow steps in order using the appropriate oracle tools. Substitute parameter_slots values as needed."
            )

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }

    // MARK: - Helpers

    private static func archReviewToDict(_ review: ArchitectureReview) -> [String: Any] {
        var d: [String: Any] = [
            "triggered": review.triggered,
            "risk_score": review.riskScore,
            "affected_modules": review.affectedModules,
        ]
        d["findings"] = review.findings.map { f -> [String: Any] in
            var fd: [String: Any] = [
                "title": f.title,
                "summary": f.summary,
                "severity": f.severity.rawValue,
                "risk_score": f.riskScore,
                "affected_modules": f.affectedModules,
            ]
            if !f.evidence.isEmpty { fd["evidence"] = f.evidence }
            return fd
        }
        if let proposal = review.refactorProposal {
            d["refactor_proposal"] = [
                "id": proposal.id,
                "title": proposal.title,
                "summary": proposal.summary,
                "steps": proposal.steps,
                "risk_score": proposal.riskScore,
            ]
        }
        return d
    }
}
