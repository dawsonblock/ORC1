import XCTest
@testable import OracleOS

/// Direct runtime behavior checks for the live MCP dispatch boundary.
@MainActor
final class MCPDispatchBehaviorTests: XCTestCase {

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