import XCTest

@testable import OracleOS

/// Direct runtime behavior checks for the live MCP dispatch boundary.
@MainActor
final class MCPDispatchBehaviorTests: XCTestCase {

    private enum TestBootstrapError: Error {
        case failed
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    func testUnknownToolReturnsErrorResponse() async {
        let start = Date()
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )

        let response = await MCPDispatch.handle(request)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("Unknown tool: oracle_not_a_real_tool"))
        XCTAssertLessThan(
            elapsed, 15, "Unknown-tool responses must not wait for the full MCP timeout")
    }

    func testExperimentSearchRejectsEmptyCandidates() async {
        let start = Date()
        let request = MCPToolRequest(
            version: "1",
            name: MCPToolName.experimentSearch,
            arguments: .object([
                "goal_description": .string("validate experiment boundary"),
                "candidates": .array([]),
            ])
        )

        let response = await MCPDispatch.handle(request)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("No valid candidates provided"))
        XCTAssertLessThan(
            elapsed, 15,
            "Empty experiment-search validation must not wait for the long async timeout")
    }

    func testBootstrapFailureReturnsExplicitErrorResponse() async {
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )
        let runtimeHost = MCPRuntimeHost {
            throw TestBootstrapError.failed
        }

        let response = await MCPDispatch.handle(
            request,
            runtimeHost: runtimeHost,
            currentWorkspaceRoot: FileManager.default.currentDirectoryPath,
            bootstrapTimeoutSeconds: 0.1,
            defaultToolTimeoutSeconds: 1
        )

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("Bootstrap failed"))
    }

    func testBootstrapTimeoutReturnsExplicitErrorResponse() async {
        let start = Date()
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )
        let runtimeHost = MCPRuntimeHost {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw TestBootstrapError.failed
        }

        let response = await MCPDispatch.handle(
            request,
            runtimeHost: runtimeHost,
            currentWorkspaceRoot: FileManager.default.currentDirectoryPath,
            bootstrapTimeoutSeconds: 0.05,
            defaultToolTimeoutSeconds: 1
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("Bootstrap timeout"))
        XCTAssertLessThan(
            elapsed, 1, "Bootstrap timeout must fail before the per-tool timeout elapses")
    }

    func testDispatchReusesBootstrappedRuntimeAcrossSequentialRequests() async throws {
        var bootstrapCount = 0
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )
        let runtimeHost = MCPRuntimeHost {
            bootstrapCount += 1
            return try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }

        let first = await MCPDispatch.handle(
            request,
            runtimeHost: runtimeHost,
            currentWorkspaceRoot: FileManager.default.currentDirectoryPath,
            bootstrapTimeoutSeconds: 5,
            defaultToolTimeoutSeconds: 1
        )
        let second = await MCPDispatch.handle(
            request,
            runtimeHost: runtimeHost,
            currentWorkspaceRoot: FileManager.default.currentDirectoryPath,
            bootstrapTimeoutSeconds: 5,
            defaultToolTimeoutSeconds: 1
        )

        XCTAssertTrue(first.isError)
        XCTAssertTrue(second.isError)
        XCTAssertEqual(bootstrapCount, 1)
    }

    func testRuntimeHostReusesBootstrappedRuntimeUntilReset() async throws {
        var bootstrapCount = 0
        let runtimeHost = MCPRuntimeHost {
            bootstrapCount += 1
            return try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }

        let first = try await runtimeHost.runtime()
        let second = try await runtimeHost.runtime()

        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertTrue(first.container === second.container)

        runtimeHost.reset()

        let third = try await runtimeHost.runtime()

        XCTAssertEqual(bootstrapCount, 2)
        XCTAssertFalse(first.container === third.container)
    }

    func testRuntimeHostDoesNotCacheBootstrapFailures() async throws {
        var bootstrapCount = 0
        let runtimeHost = MCPRuntimeHost {
            bootstrapCount += 1
            if bootstrapCount == 1 {
                throw TestBootstrapError.failed
            }
            return try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }

        do {
            _ = try await runtimeHost.runtime()
            XCTFail("Expected the first bootstrap attempt to fail")
        } catch TestBootstrapError.failed {
            XCTAssertNil(runtimeHost.existingRuntime)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let bootstrapped = try await runtimeHost.runtime()
        XCTAssertEqual(bootstrapCount, 2)
        XCTAssertTrue(bootstrapped.container === runtimeHost.existingRuntime?.container)
    }

    func testBootstrapTimeoutPolicyRemainsExplicitInSource() throws {
        let sourcePath = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("bootstrapTimeoutSeconds"),
            "MCPDispatch must define an explicit bootstrap timeout budget"
        )
        XCTAssertTrue(
            content.contains("bootstrapRuntime("),
            "MCPDispatch must separate bootstrap timing from the tool execution race"
        )
        XCTAssertTrue(
            content.contains("Bootstrap timeout"),
            "MCPDispatch must surface a deterministic bootstrap-timeout error"
        )
    }

    func testExperimentSearchRemainsExplicitAsyncExceptionPath() throws {
        let sourcePath = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("runtimeHost = MCPRuntimeHost()"),
            "MCPDispatch must delegate runtime lifecycle ownership to MCPRuntimeHost"
        )
        XCTAssertFalse(
            content.contains("_bootstrappedRuntime"),
            "MCPDispatch must not keep ad hoc static runtime state once MCPRuntimeHost exists"
        )

        XCTAssertTrue(
            content.contains("else if toolName == MCPToolName.experimentSearch")
                && content.contains("result = await handleExperimentSearch(request)"),
            "oracle_experiment_search must remain an explicit async branch in MCPDispatch.handle"
        )
        XCTAssertTrue(
            content.contains("bootstrapped.container.experimentManager.run(spec: spec)"),
            "oracle_experiment_search must continue to dispatch through ExperimentManager"
        )
        XCTAssertFalse(
            content.contains("case MCPToolName.experimentSearch:"),
            "oracle_experiment_search must not silently join the synchronous dispatch(request:) switch"
        )
    }

    func testExperimentSearchSerializationAdvertisesSandboxOnlyContext() throws {
        let sourcePath = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("executionContext = \"execution_context\""),
            "Experiment MCP responses must publish an explicit execution_context field"
        )
        XCTAssertTrue(
            content.contains("committedToWorkspace = \"committed_to_workspace\""),
            "Experiment MCP responses must publish a committed_to_workspace flag"
        )
        XCTAssertTrue(
            content.contains("sandboxPath = \"sandbox_path\""),
            "Experiment MCP responses must continue to expose sandbox_path for sandbox-only results"
        )
    }

    func testObservationalAndExperimentalToolsRemainExplicitDispatchPaths() throws {
        let sourcePath = repositoryRoot().appendingPathComponent(
            "Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("if toolName == MCPToolName.screenshot")
                && content.contains("result = await handleScreenshot(request)"),
            "oracle_screenshot must remain an explicit read-only special handler"
        )
        XCTAssertTrue(
            content.contains("case MCPToolName.wait:")
                && content.contains("return WaitManager.waitFor("),
            "oracle_wait must remain an explicit host-local wait path"
        )
        XCTAssertTrue(
            content.contains("case MCPToolName.parseScreen:")
                && content.contains("return VisionScanner.parseScreen("),
            "oracle_parse_screen must remain on the optional experimental vision path"
        )
        XCTAssertTrue(
            content.contains("case MCPToolName.ground:")
                && content.contains("return VisionScanner.groundElement("),
            "oracle_ground must remain on the optional experimental vision path"
        )
    }

    func testWorkflowExecuteRunsCurrentCodeStepThroughRuntimeBridge() async throws {
        let runtimeHost = MCPRuntimeHost {
            try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }
        let bootstrapped = try await runtimeHost.runtime(
            currentWorkspaceRoot: repositoryRoot().path
        )

        let plan = WorkflowPlan(
            id: "wf-search",
            agentKind: .code,
            goalPattern: "search repository",
            steps: [
                WorkflowStep(
                    id: "step-1",
                    agentKind: .code,
                    stepPhase: .engineering,
                    actionContract: ActionContract(
                        id: "workflow|code|search",
                        agentKind: .code,
                        skillName: "searchRepository",
                        targetRole: nil,
                        targetLabel: "{{query_0}}",
                        locatorStrategy: "workflow",
                        commandCategory: CodeCommandCategory.searchCode.rawValue,
                        plannerFamily: PlannerFamily.code.rawValue
                    )
                )
            ],
            parameterSlots: ["query_0"],
            successRate: 1,
            promotionStatus: .promoted
        )
        let request = MCPToolRequest(
            version: "1",
            name: MCPToolName.workflowExecute,
            arguments: .object([
                "workflow_id": .string(plan.id),
                "parameters": .object([
                    "query_0": .string("MCPDispatch")
                ]),
            ])
        )

        let result = await MCPDispatch.executeWorkflowPlan(
            plan,
            request: request,
            container: bootstrapped.container,
            runtime: bootstrapped.orchestrator
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.data?["workflow_id"] as? String, "wf-search")
        XCTAssertEqual(result.data?["executed_step_index"] as? Int, 1)
        XCTAssertEqual(result.data?["skill"] as? String, "searchRepository")
        XCTAssertEqual(
            result.codeExecutionResult?.commandCategory, CodeCommandCategory.searchCode.rawValue)
        XCTAssertEqual(result.actionResult?.executedThroughExecutor, true)
        XCTAssertFalse(result.traceResult?.intentID.isEmpty ?? true)
    }
}

extension MCPToolResponse {
    fileprivate var textPayload: String {
        content.compactMap { item in
            if case .text(let text) = item {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}
