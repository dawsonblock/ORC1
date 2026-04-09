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
            XCTAssertFalse(content.contains("[[String: Any]]"), "\(path) must not build nested raw dictionary payloads")
            XCTAssertFalse(content.contains("[String: Any] = ["), "\(path) must not assemble ad hoc raw dictionaries")
            XCTAssertTrue(content.contains("Encodable"), "\(path) should define typed response payload models")
            XCTAssertTrue(content.contains("mcpLegacyJSONObject(from:"), "\(path) must export through the shared typed legacy seam")
        }
    }

    func testMCPToolsCatalogIsTypedSourceOfTruth() throws {
        let path = "Sources/OracleOS/MCP/MCPTools.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content.contains("struct MCPToolDefinition"))
        XCTAssertTrue(content.contains("struct MCPToolInputSchema"))
        XCTAssertTrue(content.contains("struct MCPPropertySchema"))
        XCTAssertFalse(content.contains("private static let perception: [[String: Any]]"))
        XCTAssertFalse(content.contains("private static func tool(") && content.contains("-> [String: Any]"))
    }

    func testControllerBridgeConsumesTypedResultFields() throws {
        let path = "Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content.contains("result.actionResult"))
        XCTAssertTrue(content.contains("result.codeExecutionResult"))
        XCTAssertFalse(content.contains("result.data?["), "Controller mapping should not infer core truth from legacy dictionary probing")
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
        XCTAssertFalse(doctor.contains("JSONSerialization.jsonObject(with: data) as? [String: Any]"))
        XCTAssertTrue(config.contains("var root: [String: JSONValue]"))
    }
}
