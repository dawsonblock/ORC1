import XCTest

final class HardeningProofTests: XCTestCase {

    func testMCPDispatchCategoryFilesUseTypedSerialization() throws {
        let files = [
            "Sources/OracleOS/MCP/MCPDispatch+Workflow.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Recipes.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Memory.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Architecture.swift",
        ]

        for path in files {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            XCTAssertFalse(
                content.contains("[[String: Any]]"),
                "\(path) must not build nested raw dictionary payloads")
            XCTAssertFalse(
                content.contains("[String: Any] = ["),
                "\(path) must not assemble ad hoc raw dictionaries")
            XCTAssertTrue(
                content.contains("Encodable"), "\(path) should define typed response payload models"
            )
            XCTAssertTrue(
                content.contains("typedResult("),
                "\(path) must return payloads through the shared typed ToolResult helper")
        }

        let dispatchPath = "Sources/OracleOS/MCP/MCPDispatch.swift"
        let dispatchContent = try String(contentsOfFile: dispatchPath, encoding: .utf8)
        XCTAssertTrue(
            dispatchContent.contains("mcpLegacyJSONObject(from:"),
            "\(dispatchPath) must route typed payload export through the shared typed legacy seam")
    }

    func testMCPToolsCatalogIsTypedSourceOfTruth() throws {
        let path = "Sources/OracleOS/MCP/MCPTools.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content.contains("struct MCPToolDefinition"))
        XCTAssertTrue(content.contains("struct MCPToolInputSchema"))
        XCTAssertTrue(content.contains("struct MCPPropertySchema"))
        XCTAssertFalse(content.contains("private static let perception: [[String: Any]]"))
        XCTAssertFalse(
            content.contains("private static func tool(") && content.contains("-> [String: Any]"))
    }

    func testMCPBoundaryRequiresExplicitRequestVersion() throws {
        let path = "Sources/OracleOS/MCP/MCPBoundary.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(
            content.contains("guard let version = params[\"version\"] as? String else {")
        )
        XCTAssertTrue(content.contains("return .failure(.missingVersion)"))
        XCTAssertTrue(content.contains("sole legacy request adapter seam"))
        XCTAssertTrue(content.contains("requires an explicit"))
    }

    func testControllerBridgeConsumesTypedResultFields() throws {
        let path = "Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content.contains("result.actionResult"))
        XCTAssertTrue(content.contains("result.codeExecutionResult"))
        XCTAssertFalse(
            content.contains("result.data?["),
            "Controller mapping should not infer core truth from legacy dictionary probing")
    }

    func testCLIConfigPathsUseTypedClaudeConfigModel() throws {
        let setupPath = "Sources/oracle/SetupWizard.swift"
        let doctorPath = "Sources/oracle/Doctor.swift"
        let configPath = "Sources/oracle/ClaudeConfig.swift"

        let setup = try String(contentsOfFile: setupPath, encoding: .utf8)
        let doctor = try String(contentsOfFile: doctorPath, encoding: .utf8)
        let config = try String(contentsOfFile: configPath, encoding: .utf8)

        XCTAssertTrue(setup.contains("ClaudeConfigFile.load"))
        XCTAssertTrue(doctor.contains("ClaudeConfigFile.load"))
        XCTAssertFalse(setup.contains("JSONSerialization.jsonObject(with: data) as? [String: Any]"))
        XCTAssertFalse(
            doctor.contains("JSONSerialization.jsonObject(with: data) as? [String: Any]"))
        XCTAssertTrue(config.contains("var root: [String: JSONValue]"))
    }

    func testCLIVisionDiagnosticsReuseBridgeStatusTruth() throws {
        let setupPath = "Sources/oracle/SetupWizard.swift"
        let doctorPath = "Sources/oracle/Doctor.swift"

        let setup = try String(contentsOfFile: setupPath, encoding: .utf8)
        let doctor = try String(contentsOfFile: doctorPath, encoding: .utf8)

        XCTAssertTrue(
            setup.contains("VisionBridge.sidecarStatus()"),
            "SetupWizard should consume the shared bridge sidecar status truth"
        )
        XCTAssertTrue(
            doctor.contains("VisionBridge.sidecarStatus()"),
            "Doctor should consume the shared bridge sidecar status truth"
        )
    }

    func testServicePersistenceSurfacesStayBoundedAndExplicit() throws {
        let guardPath = "scripts/execution_boundary_guard.py"
        let recipeStorePath = "Sources/OracleOS/Learning/Recipes/RecipeStore.swift"
        let workflowIndexPath = "Sources/OracleOS/Planning/Workflows/WorkflowIndex.swift"
        let projectMemoryStorePath = "Sources/OracleOS/Learning/Project/ProjectMemoryStore.swift"
        let recipeDispatchPath = "Sources/OracleOS/MCP/MCPDispatch+Recipes.swift"
        let workflowDispatchPath = "Sources/OracleOS/MCP/MCPDispatch+Workflow.swift"
        let memoryDispatchPath = "Sources/OracleOS/MCP/MCPDispatch+Memory.swift"

        let guardContent = try String(contentsOfFile: guardPath, encoding: .utf8)
        let recipeStore = try String(contentsOfFile: recipeStorePath, encoding: .utf8)
        let workflowIndex = try String(contentsOfFile: workflowIndexPath, encoding: .utf8)
        let projectMemoryStore = try String(contentsOfFile: projectMemoryStorePath, encoding: .utf8)
        let recipeDispatch = try String(contentsOfFile: recipeDispatchPath, encoding: .utf8)
        let workflowDispatch = try String(contentsOfFile: workflowDispatchPath, encoding: .utf8)
        let memoryDispatch = try String(contentsOfFile: memoryDispatchPath, encoding: .utf8)

        let writeAuthorities = [
            "Sources/OracleOS/Learning/Recipes/RecipeStore.swift",
            "Sources/OracleOS/Learning/Project/ProjectMemoryIndexer.swift",
            "Sources/OracleOS/Learning/Project/ProjectMemoryStore.swift",
            "Sources/OracleOS/Planning/Workflows/WorkflowIndex.swift",
        ]

        for authority in writeAuthorities {
            XCTAssertTrue(
                guardContent.contains("\"\(authority)\""),
                "execution_boundary_guard.py must explicitly bless service-persistence write authority: \(authority)"
            )
        }

        XCTAssertTrue(recipeStore.contains("BOUNDED SERVICE PERSISTENCE"))
        XCTAssertTrue(workflowIndex.contains("BOUNDED SERVICE PERSISTENCE"))
        XCTAssertTrue(projectMemoryStore.contains("NOT live runtime memory"))
        XCTAssertTrue(recipeDispatch.contains("bounded service surface"))
        XCTAssertTrue(workflowDispatch.contains("bounded service-persistence surface"))
        XCTAssertTrue(memoryDispatch.contains("bounded service-persistence surface"))

        XCTAssertTrue(recipeDispatch.contains("RecipeStore."))
        XCTAssertTrue(workflowDispatch.contains("WorkflowIndex()"))
        XCTAssertTrue(memoryDispatch.contains("container.memoryStore"))

        let boundedEntrypoints = [
            (recipeDispatchPath, recipeDispatch),
            (workflowDispatchPath, workflowDispatch),
            (memoryDispatchPath, memoryDispatch),
        ]

        for (path, content) in boundedEntrypoints {
            XCTAssertFalse(
                content.contains("CommitCoordinator("),
                "\(path) must not instantiate CommitCoordinator"
            )
            XCTAssertFalse(
                content.contains("VerifiedExecutor("),
                "\(path) must not instantiate VerifiedExecutor"
            )
            XCTAssertFalse(
                content.contains("makeBootstrappedRuntime"),
                "\(path) must not bootstrap its own runtime authority"
            )
        }
    }

    func testWorkflowExecuteRemainsTypedRuntimeExecutionPath() throws {
        let workflowDispatchPath = "Sources/OracleOS/MCP/MCPDispatch+Workflow.swift"
        let workflowDispatch = try String(contentsOfFile: workflowDispatchPath, encoding: .utf8)

        XCTAssertTrue(
            workflowDispatch.contains("struct WorkflowExecutionPayload: Encodable"),
            "\(workflowDispatchPath) must keep a typed workflow execution payload model"
        )
        XCTAssertTrue(
            workflowDispatch.contains("return await executeWorkflowPlan("),
            "\(workflowDispatchPath) must route oracle_workflow_execute through the dedicated execution path"
        )
        XCTAssertTrue(
            workflowDispatch.contains("let payload = WorkflowExecutionPayload("),
            "\(workflowDispatchPath) must build the typed workflow execution payload before export"
        )
        XCTAssertTrue(
            workflowDispatch.contains("guard let data = legacyDict(for: payload) else {"),
            "\(workflowDispatchPath) must export workflow execution payloads through the shared typed legacy seam"
        )
        XCTAssertTrue(
            workflowDispatch.contains(
                "RuntimeExecutionDriver(intentAPI: runtime, surface: .mcp).execute("),
            "\(workflowDispatchPath) must keep workflow execution on the runtime execution spine"
        )
        XCTAssertTrue(
            workflowDispatch.contains("actionResult: runtimeResult.actionResult"),
            "\(workflowDispatchPath) must preserve typed action results when merging workflow execution output"
        )
        XCTAssertTrue(
            workflowDispatch.contains("traceResult: runtimeResult.traceResult"),
            "\(workflowDispatchPath) must preserve typed trace results when merging workflow execution output"
        )
        XCTAssertTrue(
            workflowDispatch.contains("codeExecutionResult: runtimeResult.codeExecutionResult"),
            "\(workflowDispatchPath) must preserve typed code execution results when merging workflow execution output"
        )
    }
}
