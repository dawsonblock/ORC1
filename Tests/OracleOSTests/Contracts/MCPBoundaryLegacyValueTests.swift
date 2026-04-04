import XCTest
@testable import OracleOS

final class MCPBoundaryLegacyValueTests: XCTestCase {

    func testFromLegacyValue_arrayRoundtrip() {
        let value: [Any] = [1, "two", true]
        let decoded = JSONValue.from(legacyValue: value)
        XCTAssertEqual(decoded, .array([.int(1), .string("two"), .bool(true)]))
    }

    func testFromLegacyValue_scalarRoundtrip() {
        XCTAssertEqual(JSONValue.from(legacyValue: "hello"), .string("hello"))
        XCTAssertEqual(JSONValue.from(legacyValue: 7), .int(7))
    }

    func testFromLegacyValue_nonSerializableReturnsNil() {
        final class NotJSON {}
        XCTAssertNil(JSONValue.from(legacyValue: NotJSON()))
    }

    func testDecodeFromLegacyDict_arrayArgumentsAccepted() {
        let params: [String: Any] = [
            "name": "oracle_hotkey",
            "arguments": ["cmd", "shift", "p"],
        ]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertEqual(req?.arguments, .array([.string("cmd"), .string("shift"), .string("p")]))
    }

    func testDecodeFromLegacyDict_scalarArgumentsAccepted() {
        let params: [String: Any] = [
            "name": "oracle_recipe_show",
            "arguments": "draft",
        ]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertEqual(req?.arguments, .string("draft"))
    }

    func testDecodeFromLegacyDict_invalidArgumentsReturnNil() {
        final class NotJSON {}
        let params: [String: Any] = [
            "name": "oracle_click",
            "arguments": ["bad": NotJSON()],
        ]
        XCTAssertNil(MCPToolRequest.decode(from: params))
    }
}
