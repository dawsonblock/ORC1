import Foundation

private struct ExperimentCommandResultSummary: Encodable {
    let succeeded: Bool
    let exitCode: Int
    let summary: String

    enum CodingKeys: String, CodingKey {
        case succeeded
        case exitCode = "exit_code"
        case summary
    }
}

private struct ExperimentSearchResultSummary: Encodable {
    let id: String
    let selected: Bool
    let executionContext: String
    let committedToWorkspace: Bool
    let candidateTitle: String
    let candidatePath: String
    let sandboxPath: String
    let architectureRisk: Double
    let diffSummary: String
    let commandResults: [ExperimentCommandResultSummary]
    let resolvedSandboxRoot: String?
    let canonicalWorkspaceRoot: String?
    let candidatePaths: [String]?
    let executedCommands: [String]?
    let cleanupOutcome: ExperimentCleanupOutcome?
    let commitCoordinatorMutation: Bool?
    let approvalStorePromotion: Bool?
    let liveRuntimeStateMutation: Bool?
    let workspaceWritebackOutsideSandbox: Bool?
    let sandboxMetadata: SandboxExecutionMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case selected
        case executionContext = "execution_context"
        case committedToWorkspace = "committed_to_workspace"
        case candidateTitle = "candidate_title"
        case candidatePath = "candidate_path"
        case sandboxPath = "sandbox_path"
        case architectureRisk = "architecture_risk"
        case diffSummary = "diff_summary"
        case commandResults = "command_results"
        case resolvedSandboxRoot = "resolved_sandbox_root"
        case canonicalWorkspaceRoot = "canonical_workspace_root"
        case candidatePaths = "candidate_paths"
        case executedCommands = "executed_commands"
        case cleanupOutcome = "cleanup_outcome"
        case commitCoordinatorMutation = "commit_coordinator_mutation"
        case approvalStorePromotion = "approval_store_promotion"
        case liveRuntimeStateMutation = "live_runtime_state_mutation"
        case workspaceWritebackOutsideSandbox = "workspace_writeback_outside_sandbox"
        case sandboxMetadata = "sandbox_metadata"
    }
}

private struct ExperimentSearchPayload: Encodable {
    let results: [ExperimentSearchResultSummary]
    let count: Int
}

// MCPDispatch.swift — Routes all 30 MCP tool calls to their backing implementations.
//
// Tool coverage is enforced by two guards:
//   scripts/mcp_boundary_guard.py      – CI shell check
//   Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift – Swift unit test
//
// Architecture note: the public async handle entrypoint is not main-actor bound.
// It starts a bounded bootstrap race before the tool-specific timeout race so
// MCP bootstrap latency cannot sit outside the public timeout contract. The
// synchronous dispatch(request:) path still runs on @MainActor. oracle_screenshot
// remains an explicit read-only special handler, and oracle_experiment_search
// remains the sole async sandbox exception because ExperimentManager.run() is
// async throws.

public enum MCPDispatch {
    private static let bootstrapTimeoutSeconds: TimeInterval = 15
    private static let toolTimeoutSeconds: TimeInterval = 60
    @MainActor private static let runtimeHost = MCPRuntimeHost()

    // MARK: - Public entry points

    @MainActor
    public static func handle(_ params: [String: Any]) async -> [String: Any] {
        switch MCPToolRequest.decodeResult(from: params) {
        case .success(let request):
            return await handle(request).toLegacyDict()
        case .failure(let reason):
            return formatTypedResult(
                ToolResult(success: false, error: reason.localizedDescription),
                toolName: "mcp_request_decode_failure"
            ).toLegacyDict()
        }
    }

    public static func handle(_ request: MCPToolRequest) async -> MCPToolResponse {
        let runtimeHost = await MainActor.run { MCPDispatch.runtimeHost }
        return await handle(
            request,
            runtimeHost: runtimeHost,
            currentWorkspaceRoot: FileManager.default.currentDirectoryPath,
            bootstrapTimeoutSeconds: bootstrapTimeoutSeconds,
            defaultToolTimeoutSeconds: toolTimeoutSeconds
        )
    }

    static func handle(
        _ request: MCPToolRequest,
        runtimeHost: MCPRuntimeHost,
        currentWorkspaceRoot: String,
        bootstrapTimeoutSeconds: TimeInterval,
        defaultToolTimeoutSeconds: TimeInterval
    ) async -> MCPToolResponse {
        switch await bootstrapRuntime(
            using: runtimeHost,
            currentWorkspaceRoot: currentWorkspaceRoot,
            timeoutSeconds: bootstrapTimeoutSeconds
        ) {
        case .ready:
            break
        case .failed(let message):
            return .error(message)
        case .timedOut:
            return .error("Bootstrap timeout")
        }

        let toolName = request.name
        let actualTimeout = toolName == MCPToolName.experimentSearch ? 600.0 : defaultToolTimeoutSeconds

        struct RespWrapper: @unchecked Sendable { let payload: MCPToolResponse? }
        let response: RespWrapper
        do {
            response = try await withThrowingTaskGroup(of: RespWrapper.self) { group in
                group.addTask { @Sendable in
                    let result: MCPToolResponse
                    if toolName == MCPToolName.screenshot {
                        result = await handleScreenshot(request)
                    } else if toolName == MCPToolName.experimentSearch {
                        result = await handleExperimentSearch(request)
                    } else {
                        let dispatched = await dispatch(request: request)
                        result = formatTypedResult(dispatched, toolName: toolName)
                    }
                    return RespWrapper(payload: result)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(actualTimeout * 1_000_000_000))
                    return RespWrapper(payload: nil)
                }
                let first = try await group.next() ?? RespWrapper(payload: nil)
                group.cancelAll()
                return first
            }
        } catch { response = RespWrapper(payload: nil) }

        return response.payload ?? .error("Timeout")
    }

    private enum BootstrapStatus: Sendable {
        case ready
        case timedOut
        case failed(String)
    }

    private static func bootstrapRuntime(
        using runtimeHost: MCPRuntimeHost,
        currentWorkspaceRoot: String,
        timeoutSeconds: TimeInterval
    ) async -> BootstrapStatus {
        let bootstrapTask = Task { @MainActor in
            try await runtimeHost.runtime(currentWorkspaceRoot: currentWorkspaceRoot)
        }

        let result = await withTaskGroup(of: BootstrapStatus.self) { group in
            group.addTask {
                do {
                    _ = try await bootstrapTask.value
                    return .ready
                } catch {
                    return .failed("Bootstrap failed")
                }
            }
            group.addTask {
                let duration = max(timeoutSeconds, 0)
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next() ?? .failed("Bootstrap failed")
            bootstrapTask.cancel()
            group.cancelAll()
            return first
        }

        return result
    }

    // MARK: - Special handlers

    @MainActor
    private static func handleScreenshot(_ request: MCPToolRequest) -> MCPToolResponse {
        let res = AXScanner.screenshot(appName: request.string("app"), fullResolution: request.bool("full_resolution") ?? false)
        guard res.success, let screenshot = res.screenshotResult else {
            return formatTypedResult(res, toolName: MCPToolName.screenshot)
        }
        return .imageAndCaption(base64: screenshot.base64PNG, mimeType: screenshot.mimeType, caption: "Screenshot")
    }

    @MainActor
    private static func handleExperimentSearch(_ request: MCPToolRequest) async -> MCPToolResponse {
        guard let bootstrapped = runtimeHost.existingRuntime else {
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
                toolName: MCPToolName.experimentSearch
            )
        }
        let buildCommandResult = makeExperimentCommandRequest(request.strings("build_command"), category: .build)
        switch buildCommandResult {
        case .failure(let error):
            return formatTypedResult(
                ToolResult(success: false, error: error),
                toolName: MCPToolName.experimentSearch
            )
        case .success:
            break
        }
        let testCommandResult = makeExperimentCommandRequest(request.strings("test_command"), category: .test)
        switch testCommandResult {
        case .failure(let error):
            return formatTypedResult(
                ToolResult(success: false, error: error),
                toolName: MCPToolName.experimentSearch
            )
        case .success:
            break
        }
        let spec = ExperimentSpec(
            goalDescription: goalDescription,
            workspaceRoot: FileManager.default.currentDirectoryPath,
            candidates: patches,
            buildCommand: try? buildCommandResult.get(),
            testCommand: try? testCommandResult.get()
        )
        do {
            let results = try await bootstrapped.container.experimentManager.run(spec: spec)
            let payload = ExperimentSearchPayload(
                results: results.map { result in
                    ExperimentSearchResultSummary(
                        id: result.id,
                        selected: result.selected,
                        executionContext: result.executionContext.rawValue,
                        committedToWorkspace: result.committedToWorkspace,
                        candidateTitle: result.candidate.title,
                        candidatePath: result.candidate.workspaceRelativePath,
                        sandboxPath: result.sandboxPath,
                        architectureRisk: result.architectureRiskScore,
                        diffSummary: result.diffSummary,
                        commandResults: result.commandResults.map { commandResult in
                            ExperimentCommandResultSummary(
                                succeeded: commandResult.succeeded,
                                exitCode: Int(commandResult.exitCode),
                                summary: commandResult.summary
                            )
                        },
                        resolvedSandboxRoot: result.sandboxEvidence?.resolvedSandboxRoot,
                        canonicalWorkspaceRoot: result.sandboxEvidence?.canonicalWorkspaceRoot,
                        candidatePaths: result.sandboxEvidence?.candidatePaths,
                        executedCommands: result.sandboxEvidence?.executedCommands,
                        cleanupOutcome: result.sandboxEvidence?.cleanupOutcome,
                        commitCoordinatorMutation: result.sandboxEvidence?.commitCoordinatorMutation,
                        approvalStorePromotion: result.sandboxEvidence?.approvalStorePromotion,
                        liveRuntimeStateMutation: result.sandboxEvidence?.liveRuntimeStateMutation,
                        workspaceWritebackOutsideSandbox: result.sandboxEvidence?.workspaceWritebackOutsideSandbox
                    )
                },
                count: results.count
            )
            return exportTypedResponse(payload, toolName: MCPToolName.experimentSearch)
        } catch {
            return formatTypedResult(
                ToolResult(success: false, error: "Experiment search failed: \(error)"),
                toolName: MCPToolName.experimentSearch
            )
        }
    }

    private static func makeExperimentCommandRequest(
        _ args: [String]?,
        category: CodeCommandCategory
    ) -> Result<ExperimentCommandRequest?, String> {
        guard let args, !args.isEmpty else { return .success(nil) }
        let executable = args[0]
        let allowlist: Set<String> = category == .build
            ? ["/usr/bin/swift", "swift", "/usr/bin/xcodebuild", "xcodebuild"]
            : ["/usr/bin/swift", "swift", "/usr/bin/xcodebuild", "xcodebuild"]
        guard allowlist.contains(executable) else {
            let sorted = allowlist.sorted().joined(separator: ", ")
            return .failure(
                "Unsupported \(category.rawValue) command executable '\(executable)'. Allowed executables: \(sorted)."
            )
        }
        return .success(ExperimentCommandRequest(
            category: category,
            executable: executable,
            arguments: Array(args.dropFirst()),
            summary: args.joined(separator: " ")
        ))
    }

    static func legacyDict<T: Encodable>(for value: T) -> [String: Any]? {
        let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.sortedKeys])
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    static func typedResult<T: Encodable>(
        _ payload: T,
        suggestion: String? = nil
    ) -> ToolResult {
        guard let data = legacyDict(for: payload) else {
            return ToolResult(success: false, error: "Failed to serialize \(T.self)")
        }
        return ToolResult(success: true, data: data, suggestion: suggestion)
    }

    private static func exportTypedResponse<T: Encodable>(
        _ payload: T,
        toolName: String
    ) -> MCPToolResponse {
        formatTypedResult(typedResult(payload), toolName: toolName)
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

    @MainActor
    private static func dispatch(request: MCPToolRequest) -> ToolResult {
        let tool = request.name
        guard let bootstrapped = runtimeHost.existingRuntime else {
            return ToolResult(success: false, error: "Runtime not bootstrapped")
        }
        let container = bootstrapped.container
        let runtime = bootstrapped.orchestrator

        switch tool {

        // MARK: Perception

        case MCPToolName.context:
            return AXScanner.getContext(appName: request.string("app"))

        case MCPToolName.state:
            return AXScanner.getState(appName: request.string("app"))

        case MCPToolName.find:
            return AXScanner.findElements(
                query: request.string("query"),
                role: request.string("role"),
                domId: request.string("dom_id"),
                domClass: request.string("dom_class"),
                identifier: request.string("identifier"),
                appName: request.string("app"),
                depth: request.int("depth")
            )

        case MCPToolName.read:
            return AXScanner.readContent(
                appName: request.string("app"),
                query: request.string("query"),
                depth: request.int("depth")
            )

        case MCPToolName.inspect:
            return AXScanner.inspect(
                query: request.string("query") ?? "",
                role: request.string("role"),
                domId: request.string("dom_id"),
                appName: request.string("app")
            )

        case MCPToolName.elementAt:
            guard let x = request.double("x"), let y = request.double("y") else {
                return ToolResult(success: false, error: "x and y are required for oracle_element_at")
            }
            return AXScanner.elementAt(x: x, y: y)

        // MARK: Actions

        case MCPToolName.click:
            return FocusManager.withFocusRestore {
                Actions.click(
                    query: request.string("query"),
                    role: request.string("role"),
                    domId: request.string("dom_id"),
                    appName: request.string("app"),
                    x: request.double("x"),
                    y: request.double("y"),
                    button: request.string("button"),
                    count: request.int("count"),
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: request.string("approval_request_id"),
                    toolName: tool
                )
            }

        case MCPToolName.type_:
            return FocusManager.withFocusRestore {
                Actions.typeText(
                    text: request.string("text") ?? "",
                    into: request.string("into"),
                    domId: request.string("dom_id"),
                    appName: request.string("app"),
                    clear: request.bool("clear") ?? false,
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: request.string("approval_request_id"),
                    toolName: tool
                )
            }

        case MCPToolName.press:
            guard let key = request.string("key") else {
                return ToolResult(success: false, error: "key is required for oracle_press")
            }
            return Actions.pressKey(
                key: key,
                modifiers: request.strings("modifiers"),
                appName: request.string("app"),
                runtime: runtime,
                approvalRequestID: request.string("approval_request_id")
            )

        case MCPToolName.hotkey:
            guard let keys = request.strings("keys"), !keys.isEmpty else {
                return ToolResult(success: false, error: "keys array is required for oracle_hotkey")
            }
            return Actions.hotkey(
                keys: keys,
                appName: request.string("app"),
                runtime: runtime,
                approvalRequestID: request.string("approval_request_id")
            )

        case MCPToolName.scroll:
            guard let direction = request.string("direction") else {
                return ToolResult(success: false, error: "direction is required for oracle_scroll")
            }
            return Actions.scroll(
                direction: direction,
                amount: request.int("amount"),
                appName: request.string("app"),
                x: request.double("x"),
                y: request.double("y"),
                runtime: runtime,
                approvalRequestID: request.string("approval_request_id")
            )

        case MCPToolName.focus:
            guard let appName = request.string("app") else {
                return ToolResult(success: false, error: "app is required for oracle_focus")
            }
            return Actions.focusApp(
                appName: appName,
                windowTitle: request.string("window"),
                runtime: runtime,
                approvalRequestID: request.string("approval_request_id")
            )

        case MCPToolName.window:
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
                runtime: runtime,
                approvalRequestID: request.string("approval_request_id")
            )

        // MARK: Wait (read-only host-local polling)

        case MCPToolName.wait:
            return WaitManager.waitFor(
                condition: request.string("condition") ?? "",
                value: request.string("value"),
                appName: request.string("app"),
                timeout: request.double("timeout") ?? 10,
                interval: request.double("interval") ?? 0.5
            )

        // MARK: Vision (optional experimental perception)

        case MCPToolName.parseScreen:
            return VisionScanner.parseScreen(
                appName: request.string("app"),
                fullResolution: request.bool("full_resolution") ?? false
            )

        case MCPToolName.ground:
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

        case MCPToolName.recipes, MCPToolName.run, MCPToolName.recipeShow, MCPToolName.recipeSave, MCPToolName.recipeDelete:
            return dispatchRecipes(request, runtime: runtime)

        // MARK: Project Memory

        case MCPToolName.memoryQuery, MCPToolName.memoryDraft:
            return dispatchMemory(request, container: container)

        // MARK: Architecture

        case MCPToolName.architectureReview, MCPToolName.candidateReview:
            return dispatchArchitecture(request, container: container)

        // MARK: Workflows

        case MCPToolName.workflowList, MCPToolName.workflowMine, MCPToolName.workflowExecute:
            return dispatchWorkflow(request, container: container)

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }
}
