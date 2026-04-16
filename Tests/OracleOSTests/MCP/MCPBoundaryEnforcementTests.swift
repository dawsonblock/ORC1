import XCTest

@testable import OracleOS

/// Governance tests for the MCP transport boundary.
///
/// These tests enforce that the canonical types for the MCP boundary live in a
/// single location and expose the required accessors and shape. They also verify
/// that the dispatch implementation adheres to typed parameter extraction.
final class MCPBoundaryEnforcementTests: XCTestCase {

    /// Verify that the canonical boundary file defines all of the expected types.
    func testMCPBoundaryIsCanonical() throws {
        let boundaryPath = "Sources/OracleOS/MCP/MCPBoundary.swift"
        let content = try String(contentsOfFile: boundaryPath, encoding: .utf8)
        XCTAssertTrue(content.contains("enum JSONValue"), "MCPBoundary must define JSONValue")
        XCTAssertTrue(
            content.contains("struct MCPToolRequest"), "MCPBoundary must define MCPToolRequest")
        XCTAssertTrue(
            content.contains("struct MCPToolResponse"), "MCPBoundary must define MCPToolResponse")
        XCTAssertTrue(content.contains("enum MCPContent"), "MCPBoundary must define MCPContent")
    }

    /// Verify that JSONValue exposes typed accessor properties.
    func testJSONValueHasTypedAccessors() throws {
        let boundaryPath = "Sources/OracleOS/MCP/MCPBoundary.swift"
        let content = try String(contentsOfFile: boundaryPath, encoding: .utf8)
        let requiredAccessors = [
            "stringValue",
            "intValue",
            "doubleValue",
            "boolValue",
            "arrayValue",
            "objectValue",
        ]
        for accessor in requiredAccessors {
            XCTAssertTrue(content.contains(accessor), "JSONValue must define \(accessor)")
        }
    }

    /// Verify MCPToolRequest uses JSONValue for arguments and has helper accessors.
    func testMCPToolRequestUsesJSONValue() throws {
        let boundaryPath = "Sources/OracleOS/MCP/MCPBoundary.swift"
        let content = try String(contentsOfFile: boundaryPath, encoding: .utf8)
        XCTAssertTrue(
            content.contains("arguments: JSONValue"), "MCPToolRequest.arguments must be JSONValue")
        XCTAssertTrue(content.contains("func string("), "MCPToolRequest must have string() helper")
        XCTAssertTrue(content.contains("func bool("), "MCPToolRequest must have bool() helper")
        XCTAssertTrue(content.contains("func int("), "MCPToolRequest must have int() helper")
    }

    /// Verify Dispatch uses the typed handle entrypoint.
    func testMCPDispatchUsesTypedHandle() throws {
        let dispatchPath = "Sources/OracleOS/MCP/MCPDispatch.swift"
        let content = try String(contentsOfFile: dispatchPath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("func dispatch(request: MCPToolRequest)"),
            "dispatch(request:) must be typed"
        )
        XCTAssertTrue(
            content.contains("func handle(_ params: [String: Any])"),
            "Legacy handle must exist"
        )
        XCTAssertTrue(
            content.contains("return await handle(request).toLegacyDict()"),
            "Legacy handle must call typed handle"
        )
    }

    /// Verify no raw dictionary casts in the dispatch body.
    func testNoRawDictionaryCastsInDispatch() throws {
        let dispatchPath = "Sources/OracleOS/MCP/MCPDispatch.swift"
        let content = try String(contentsOfFile: dispatchPath, encoding: .utf8)

        // Isolate the dispatch function body (approximate search)
        guard
            let dispatchStart = content.range(
                of: "private static func dispatch(request: MCPToolRequest)")?.upperBound,
            let dispatchEnd = content.range(
                of: "default:", range: dispatchStart..<content.endIndex)?.lowerBound
        else {
            XCTFail("Could not locate dispatch(request:) body")
            return
        }

        let dispatchBody = String(content[dispatchStart..<dispatchEnd])
        XCTAssertFalse(
            dispatchBody.contains("as? [String: Any]"),
            "Dispatch body should not contain raw dictionary casts")
        XCTAssertFalse(
            dispatchBody.contains("as! [String: Any]"),
            "Dispatch body should not contain raw dictionary casts")
    }
}
