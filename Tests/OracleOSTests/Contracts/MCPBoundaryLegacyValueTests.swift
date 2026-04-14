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
        // Uses a fake tool name to avoid implying oracle_hotkey supports array-shaped arguments.
        // This test only exercises boundary decoding permissiveness, not tool-specific schemas.
        let params: [String: Any] = [
            "name": "oracle_test_array_args",
            "arguments": ["cmd", "shift", "p"],
        ]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertEqual(req?.arguments, .array([.string("cmd"), .string("shift"), .string("p")]))
    }

    func testDecodeFromLegacyDict_scalarArgumentsAccepted() {
        // Uses a fake tool name to avoid implying oracle_recipe_show supports scalar arguments.
        // This test only exercises boundary decoding permissiveness, not tool-specific schemas.
        let params: [String: Any] = [
            "name": "oracle_test_scalar_args",
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

    func testDecodeResultFromLegacyDict_invalidArgumentsReturnTypedError() {
        final class NotJSON {}
        let params: [String: Any] = [
            "name": "oracle_click",
            "arguments": ["bad": NotJSON()],
        ]
        let result = MCPToolRequest.decodeResult(from: params)
        if case .failure(let failure) = result {
            XCTAssertEqual(failure, .invalidArguments)
        } else {
            XCTFail("Expected .failure(.invalidArguments), got \(result)")
        }
    }

    func testDecodeResultFromLegacyDict_missingNameReturnTypedError() {
        let params: [String: Any] = ["arguments": "value"]
        let result = MCPToolRequest.decodeResult(from: params)
        if case .failure(let failure) = result {
            XCTAssertEqual(failure, .missingName)
        } else {
            XCTFail("Expected .failure(.missingName), got \(result)")
        }
    }

    func testDecodeResultFromLegacyDict_missingVersionReturnTypedError() {
        let params: [String: Any] = [
            "name": "oracle_click",
            "arguments": ["app": "Notes"],
        ]
        let result = MCPToolRequest.decodeResult(from: params)
        if case .failure(let failure) = result {
            XCTAssertEqual(failure, .missingVersion)
        } else {
            XCTFail("Expected .failure(.missingVersion), got \(result)")
        }
    }

    func testDecodeResultFromLegacyDict_unsupportedVersionReturnTypedError() {
        let params: [String: Any] = ["name": "oracle_click", "version": "99"]
        let result = MCPToolRequest.decodeResult(from: params)
        if case .failure(let failure) = result {
            XCTAssertEqual(failure, .unsupportedVersion("99"))
        } else {
            XCTFail("Expected .failure(.unsupportedVersion), got \(result)")
        }
    }
}
