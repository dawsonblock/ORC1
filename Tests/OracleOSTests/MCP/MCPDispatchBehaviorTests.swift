import XCTest
@testable import OracleOS

/// Direct runtime behavior checks for the live MCP dispatch boundary.
@MainActor
final class MCPDispatchBehaviorTests: XCTestCase {

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    func testUnknownToolReturnsErrorResponse() async {
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )

        let response = await MCPDispatch.handle(request)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("Unknown tool: oracle_not_a_real_tool"))
    }

    func testExperimentSearchRejectsEmptyCandidates() async {
        let request = MCPToolRequest(
            version: "1",
            name: MCPToolName.experimentSearch,
            arguments: .object([
                "goal_description": .string("validate experiment boundary"),
                "candidates": .array([]),
            ])
        )

        let response = await MCPDispatch.handle(request)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("No valid candidates provided"))
    }

    func testExperimentSearchRemainsExplicitAsyncExceptionPath() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

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
}

private extension MCPToolResponse {
    var textPayload: String {
        content.compactMap { item in
            if case .text(let text) = item {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
}