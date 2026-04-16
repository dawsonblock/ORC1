import Foundation
import Testing

@testable import OracleController
@testable import OracleControllerShared

@MainActor
struct HostProcessClientTests {
    @Test
    func resolveHostURLPrefersExplicitOverride() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let override = try makeExecutable(at: root.appendingPathComponent("override-host"))
        let bundled = try makeExecutable(at: root.appendingPathComponent("bundled-host"))
        let fallback = try makeExecutable(at: root.appendingPathComponent("fallback-host"))

        let resolved = try HostProcessClient.resolveHostURL(
            using: makeResolutionContext(
                environment: ["ORACLE_CONTROLLER_HOST_PATH": override.path],
                bundledHelperURL: bundled,
                siblingHelperURL: root.appendingPathComponent("OracleControllerHost"),
                developerFallbackURLs: [fallback],
                launchCurrentDirectoryURL: root
            )
        )

        #expect(resolved.path == override.path)
    }

    @Test
    func resolveHostURLPrefersBundledHelperBeforeDeveloperFallback() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = try makeExecutable(at: root.appendingPathComponent("bundled-host"))
        let fallback = try makeExecutable(at: root.appendingPathComponent("fallback-host"))

        let resolved = try HostProcessClient.resolveHostURL(
            using: makeResolutionContext(
                bundledHelperURL: bundled,
                siblingHelperURL: root.appendingPathComponent("OracleControllerHost"),
                developerFallbackURLs: [fallback],
                launchCurrentDirectoryURL: root
            )
        )

        #expect(resolved.path == bundled.path)
    }

    @Test
    func resolveHostURLPrefersSiblingHelperBeforeDeveloperFallbacks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sibling = try makeExecutable(at: root.appendingPathComponent("OracleControllerHost"))
        let fallback = try makeExecutable(at: root.appendingPathComponent("fallback-host"))

        let resolved = try HostProcessClient.resolveHostURL(
            using: makeResolutionContext(
                siblingHelperURL: sibling,
                developerFallbackURLs: [fallback],
                launchCurrentDirectoryURL: root
            )
        )

        #expect(resolved.path == sibling.path)
    }

    @Test
    func sendFailsFastForMissingExplicitOverride() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let bundled = try makeExecutable(at: root.appendingPathComponent("bundled-host"))
        let missingOverride = root.appendingPathComponent("missing-host")
        var lifecycleStatuses: [HostConnectionStatus] = []
        let resolutionContext = makeResolutionContext(
            environment: ["ORACLE_CONTROLLER_HOST_PATH": missingOverride.path],
            bundledHelperURL: bundled,
            siblingHelperURL: root.appendingPathComponent("OracleControllerHost"),
            developerFallbackURLs: [root.appendingPathComponent("fallback-host")],
            launchCurrentDirectoryURL: root
        )

        let client = HostProcessClient(
            eventHandler: { _ in },
            lifecycleHandler: { lifecycleStatuses.append($0) },
            hostResolutionContext: { resolutionContext }
        )

        do {
            _ = try await client.send(ControllerHostRequest(id: "ping-1", command: .ping))
            Issue.record("Expected an explicit override failure")
        } catch let error as HostClientError {
            #expect(error == .hostBinaryNotFound(path: missingOverride.path))
        }

        await waitForLifecycleEvents(&lifecycleStatuses, countAtLeast: 2)
        #expect(lifecycleStatuses.first == .launching)
        #expect(lifecycleStatuses.last?.failureReason == .binaryNotFound)
        #expect(lifecycleStatuses.last?.detail?.contains(missingOverride.path) == true)
    }

    @Test
    func sendLaunchesScriptedHostAndReceivesPingResponse() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let helper = try makeExecutable(
            at: root.appendingPathComponent("OracleControllerHost"),
            contents: """
                #!/bin/bash
                IFS= read -r _line || exit 1
                printf '%s\\n' '{"kind":"response","response":{"requestID":"ping-1","command":"ping","acknowledged":true},"event":null}'
                """
        )
        var lifecycleStatuses: [HostConnectionStatus] = []
        let resolutionContext = makeResolutionContext(
            environment: ["ORACLE_CONTROLLER_HOST_PATH": helper.path],
            bundledHelperURL: nil,
            siblingHelperURL: root.appendingPathComponent("unused-sibling"),
            developerFallbackURLs: [],
            launchCurrentDirectoryURL: root
        )

        let client = HostProcessClient(
            eventHandler: { _ in },
            lifecycleHandler: { lifecycleStatuses.append($0) },
            hostResolutionContext: { resolutionContext }
        )

        let response = try await client.send(ControllerHostRequest(id: "ping-1", command: .ping))

        #expect(response.requestID == "ping-1")
        #expect(response.command == .ping)
        #expect(response.acknowledged)

        await waitForLifecycleEvents(&lifecycleStatuses, countAtLeast: 2)
        #expect(lifecycleStatuses.first == .launching)
        #expect(lifecycleStatuses.contains(.connected))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeExecutable(at url: URL, contents: String = "#!/bin/bash\nexit 0\n") throws
        -> URL
    {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeResolutionContext(
        environment: [String: String] = [:],
        bundledHelperURL: URL? = nil,
        siblingHelperURL: URL,
        developerFallbackURLs: [URL],
        launchCurrentDirectoryURL: URL
    ) -> HostProcessResolutionContext {
        HostProcessResolutionContext(
            environment: environment,
            bundledHelperURL: bundledHelperURL,
            siblingHelperURL: siblingHelperURL,
            developerFallbackURLs: developerFallbackURLs,
            launchCurrentDirectoryURL: launchCurrentDirectoryURL
        )
    }

    private func waitForLifecycleEvents(
        _ lifecycleStatuses: inout [HostConnectionStatus],
        countAtLeast: Int
    ) async {
        for _ in 0..<100 {
            if lifecycleStatuses.count >= countAtLeast {
                return
            }
            await Task.yield()
        }
    }
}
