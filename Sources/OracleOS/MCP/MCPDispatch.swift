import Foundation

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
                    let result: MCPToolResponse = await MainActor.run {
                        if toolName == "oracle_screenshot" {
                            return handleScreenshot(request)
                        } else {
                            return formatTypedResult(dispatch(request: request), toolName: toolName)
                        }
                    }
                    return RespWrapper(payload: result)
                }
                group.addTask { try await Task.sleep(nanoseconds: UInt64(actualTimeout * 1_000_000_000)); return RespWrapper(payload: nil) }
                return try await group.next() ?? RespWrapper(payload: nil)
            }
        } catch { response = RespWrapper(payload: nil) }

        return response.payload ?? .error("Timeout")
    }

    private static func handleScreenshot(_ request: MCPToolRequest) -> MCPToolResponse {
        let res = AXScanner.screenshot(appName: request.string("app"), fullResolution: request.bool("full_resolution") ?? false)
        guard res.success, let data = res.data, let b64 = data["image"] as? String else {
            return formatTypedResult(res, toolName: "oracle_screenshot")
        }
        return .imageAndCaption(base64: b64, mimeType: data["mime_type"] as? String ?? "image/png", caption: "Screenshot")
    }

    private static func formatTypedResult(_ result: ToolResult, toolName: String) -> MCPToolResponse {
        if let data = try? JSONSerialization.data(withJSONObject: result.toDict(), options: []), let jsonStr = String(data: data, encoding: .utf8) {
            return .text(jsonStr, isError: !result.success)
        }
        return .error("Format failed")
    }

    private static func dispatch(request: MCPToolRequest) -> ToolResult {
        let tool = request.name
        let runtime = _bootstrappedRuntime!.orchestrator
        switch tool {
        case "oracle_context": return AXScanner.getContext(appName: request.string("app"))
        case "oracle_state": return AXScanner.getState(appName: request.string("app"))
        case "oracle_find": return AXScanner.findElements(query: request.string("query"), role: request.string("role"), domId: nil, domClass: nil, identifier: nil, appName: request.string("app"), depth: nil)
        case "oracle_read": return AXScanner.readContent(appName: request.string("app"), query: request.string("query"), depth: nil)
        case "oracle_click": return FocusManager.withFocusRestore { Actions.click(query: request.string("query"), role: request.string("role"), domId: nil, appName: request.string("app"), x: request.double("x"), y: request.double("y"), button: nil, count: nil, runtime: runtime, surface: .mcp, toolName: tool) }
        case "oracle_type": return FocusManager.withFocusRestore { Actions.typeText(text: request.string("text") ?? "", into: request.string("into"), domId: nil, appName: request.string("app"), clear: false, runtime: runtime, surface: .mcp, toolName: tool) }
        case "oracle_wait": return WaitManager.waitFor(condition: request.string("condition") ?? "", value: request.string("value"), appName: request.string("app"), timeout: request.double("timeout") ?? 10, interval: 0.5)
        default: return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }
}
