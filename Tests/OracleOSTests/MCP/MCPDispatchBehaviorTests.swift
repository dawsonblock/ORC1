import XCTest
@testable import OracleOS

/// Direct runtime behavior checks for the live MCP dispatch boundary.
@MainActor
final class MCPDispatchBehaviorTests: XCTestCase {

    private enum TestBootstrapError: Error {
        case failed
    }

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
        let start = Date()
        let request = MCPToolRequest(
            version: "1",
            name: "oracle_not_a_real_tool",
            arguments: .object([:])
        )

        let response = await MCPDispatch.handle(request)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("Unknown tool: oracle_not_a_real_tool"))
        XCTAssertLessThan(elapsed, 15, "Unknown-tool responses must not wait for the full MCP timeout")
    }

    func testExperimentSearchRejectsEmptyCandidates() async {
        let start = Date()
        let request = MCPToolRequest(
            version: "1",
            name: MCPToolName.experimentSearch,
            arguments: .object([
                "goal_description": .string("validate experiment boundary"),
                "candidates": .array([]),
            ])
        )

        let response = await MCPDispatch.handle(request)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(response.isError)
        XCTAssertTrue(response.textPayload.contains("No valid candidates provided"))
        XCTAssertLessThan(elapsed, 15, "Empty experiment-search validation must not wait for the long async timeout")
    }

    func testRuntimeHostReusesBootstrappedRuntimeUntilReset() async throws {
        var bootstrapCount = 0
        let runtimeHost = MCPRuntimeHost {
            bootstrapCount += 1
            return try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }

        let first = try await runtimeHost.runtime()
        let second = try await runtimeHost.runtime()

        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertTrue(first.container === second.container)

        runtimeHost.reset()

        let third = try await runtimeHost.runtime()

        XCTAssertEqual(bootstrapCount, 2)
        XCTAssertFalse(first.container === third.container)
    }

    func testRuntimeHostDoesNotCacheBootstrapFailures() async throws {
        var bootstrapCount = 0
        let runtimeHost = MCPRuntimeHost {
            bootstrapCount += 1
            if bootstrapCount == 1 {
                throw TestBootstrapError.failed
            }
            return try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .test())
        }

        do {
            _ = try await runtimeHost.runtime()
            XCTFail("Expected the first bootstrap attempt to fail")
        } catch TestBootstrapError.failed {
            XCTAssertNil(runtimeHost.existingRuntime)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let bootstrapped = try await runtimeHost.runtime()
        XCTAssertEqual(bootstrapCount, 2)
        XCTAssertTrue(bootstrapped.container === runtimeHost.existingRuntime?.container)
    }

    func testExperimentSearchRemainsExplicitAsyncExceptionPath() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/MCP/MCPDispatch.swift")
        let content = try String(contentsOf: sourcePath, encoding: .utf8)

        XCTAssertTrue(
            content.contains("runtimeHost = MCPRuntimeHost()"),
            "MCPDispatch must delegate runtime lifecycle ownership to MCPRuntimeHost"
        )
        XCTAssertFalse(
            content.contains("_bootstrappedRuntime"),
            "MCPDispatch must not keep ad hoc static runtime state once MCPRuntimeHost exists"
        )

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