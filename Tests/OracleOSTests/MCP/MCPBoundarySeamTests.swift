import XCTest
@testable import OracleOS

@MainActor
final class MCPBoundarySeamTests: XCTestCase {

    func testLegacyParamsAdapterRejectsMissingName() async {
        let params: [String: Any] = [
            "version": "1",
            "arguments": ["query": "Send"],
        ]

        let response = await MCPDispatch.handle(params)
        let content = response["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""

        XCTAssertEqual(response["isError"] as? Bool, true)
        XCTAssertTrue(text.contains("missing") || text.contains("name"), "Expected missing-name decode error, got: \(text)")
    }

    func testLegacyParamsAdapterRejectsInvalidArguments() async {
        final class NotJSON {}
        let params: [String: Any] = [
            "version": "1",
            "name": "oracle_click",
            "arguments": ["bad": NotJSON()],
        ]

        let response = await MCPDispatch.handle(params)
        let content = response["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""

        XCTAssertEqual(response["isError"] as? Bool, true)
        XCTAssertTrue(text.contains("invalidArguments") || text.contains("not JSON-serializable"),
                      "Response should surface specific decode failure reason, got: \(text)")
    }

    func testLegacyParamsAdapterAcceptsScalarArguments() async {
        let params: [String: Any] = [
            "version": "1",
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

        XCTAssertTrue(content.contains("func from(legacyValue value: Any)"),
                      "JSONValue must support generic legacy Foundation bridging via from(legacyValue:)")
    }
}
