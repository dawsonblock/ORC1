import XCTest

/// MCPToolCoverageTests — verifies that every tool declared in MCPTools.swift
/// has a matching case in MCPDispatch.swift.
///
/// This test reads the source files at test-time so it catches drift the moment
/// a developer adds a new tool without wiring it in dispatch.
final class MCPToolCoverageTests: XCTestCase {

    // MARK: - Helpers

    private func readSource(_ relativePath: String) throws -> String {
        // Tests run from the package root – fall back to two common locations.
        let candidates: [String] = [
            relativePath,
            "../../" + relativePath,
            "../../../" + relativePath,
        ]
        for path in candidates {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
        }
        // Try absolute anchor via __FILE__
        let base = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // MCP/
            .deletingLastPathComponent()   // OracleOSTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // package root
        let url = base.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func declaredToolNames(in toolsSource: String) -> [String] {
        // MCPTools.swift declares each tool as:  name: MCPToolName.<property>
        // We extract the property name and verify dispatch references MCPToolName.<property>.
        let pattern = #"name:\s*MCPToolName\.(\w+)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(toolsSource.startIndex..., in: toolsSource)
        return regex.matches(in: toolsSource, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: toolsSource) else { return nil }
            return String(toolsSource[r])
        }
    }

    // MARK: - Tests

    /// Every oracle_* tool in MCPTools.swift must appear as MCPToolName.xxx in MCPDispatch*.swift.
    func testAllDeclaredToolsAreDispatched() throws {
        let toolsSource    = try readSource("Sources/OracleOS/MCP/MCPTools.swift")
        // Combine all dispatch files so extensions (+Recipes, +Memory, etc.) are included.
        let dispatchFiles  = [
            "Sources/OracleOS/MCP/MCPDispatch.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Recipes.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Memory.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Workflow.swift",
            "Sources/OracleOS/MCP/MCPDispatch+Architecture.swift",
        ]
        let dispatchSource = dispatchFiles.compactMap { try? readSource($0) }.joined(separator: "\n")

        let declared = declaredToolNames(in: toolsSource)
        XCTAssertFalse(declared.isEmpty, "MCPTools.swift must declare at least one tool")

        var missing: [String] = []
        for name in declared {
            if !dispatchSource.contains("MCPToolName.\(name)") {
                missing.append(name)
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "MCPDispatch is missing cases for \(missing.count) tool(s): \(missing.joined(separator: ", "))"
        )
    }

    /// No tool name should be declared more than once in MCPTools.swift.
    func testNoDuplicateToolDeclarations() throws {
        let toolsSource = try readSource("Sources/OracleOS/MCP/MCPTools.swift")
        let names = declaredToolNames(in: toolsSource)

        var seen: [String: Int] = [:]
        for name in names { seen[name, default: 0] += 1 }
        let dupes = seen.filter { $0.value > 1 }.keys.sorted()

        XCTAssertTrue(
            dupes.isEmpty,
            "Duplicate tool declarations in MCPTools.swift: \(dupes.joined(separator: ", "))"
        )
    }

    /// MCPTools.swift must declare exactly 30 tools (the advertised product contract).
    func testToolCountMatchesProductContract() throws {
        let toolsSource = try readSource("Sources/OracleOS/MCP/MCPTools.swift")
        let unique = Set(declaredToolNames(in: toolsSource))
        XCTAssertEqual(unique.count, 30, "Product contract requires exactly 30 tools; found \(unique.count)")
    }
}
