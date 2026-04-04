import XCTest
@testable import OracleOS

@MainActor
final class MCPBoundarySeamTests: XCTestCase {

    func testLegacyParamsAdapterRejectsInvalidArguments() async {
        final class NotJSON {}
        let params: [String: Any] = [
            "name": "oracle_click",
            "arguments": ["bad": NotJSON()],
        ]

        let response = await MCPDispatch.handle(params)

        XCTAssertEqual(response["isError"] as? Bool, true)
    }

    func testLegacyParamsAdapterAcceptsScalarArguments() async {
        let params: [String: Any] = [
            "name": "oracle_not_a_real_tool",
            "arguments": "draft",
        ]

        let response = await MCPDispatch.handle(params)
        let content = response["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""

        XCTAssertEqual(response["isError"] as? Bool, true)
        XCTAssertTrue(text.contains("Unknown tool: oracle_not_a_real_tool"))
    }

    func testBoundaryFileDefinesGenericLegacyValueBridge() throws {
        let boundaryPath = "Sources/OracleOS/MCP/MCPBoundary.swift"
        let content = try String(contentsOfFile: boundaryPath, encoding: .utf8)

        XCTAssertTrue(content.contains("func from(legacyValue value: Any)"), "JSONValue must support generic legacy Foundation bridging")
        XCTAssertTrue(content.contains("guard let decoded = JSONValue.from(legacyValue: rawArgs) else { return nil }"),
                      "MCPToolRequest.decode(from:) must reject non-JSON arguments instead of silently collapsing them")
    }
}
