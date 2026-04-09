import XCTest

final class ControllerRuntimeMappingContractTests: XCTestCase {
    private func readSource(_ relativePath: String) throws -> String {
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: base.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testControllerMappingStaysOnTypedRuntimeFields() throws {
        let source = try readSource("Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift")

        XCTAssertTrue(source.contains("let actionResult = result.actionResult"))
        XCTAssertTrue(source.contains("let recipeRunResult = result.recipeRunResult"))
        XCTAssertTrue(source.contains("recipeRunResult?.recipeName ?? recipeName"))
        XCTAssertFalse(source.contains("result.data?[ActionResultKey.actionResult]"))
        XCTAssertFalse(source.contains("data[RecipeResultKey.stepResults] as? [[String: Any]]"))
    }
}
