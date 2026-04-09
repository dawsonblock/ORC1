import XCTest

final class ClaudeConfigRoundTripTests: XCTestCase {
    func testCLITypedClaudeConfigModelRemainsJSONValueBacked() throws {
        let path = "/home/runner/work/ORC1/ORC1/Sources/oracle/ClaudeConfig.swift"
        let content = try String(contentsOfFile: path, encoding: .utf8)

        XCTAssertTrue(content.contains("var root: [String: JSONValue]"))
        XCTAssertTrue(content.contains("mutating func setServer"))
        XCTAssertTrue(content.contains("mutating func ensureAllowedTool"))
        XCTAssertTrue(content.contains("func write(to path: String) throws"))
        XCTAssertFalse(content.contains("JSONSerialization.jsonObject(with:"))
    }
}
