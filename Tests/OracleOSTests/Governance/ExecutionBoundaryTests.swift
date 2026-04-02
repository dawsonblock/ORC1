import XCTest
@testable import OracleOS

final class ExecutionBoundaryTests: XCTestCase {
    func testVerifiedExecutorRestrictsCommands() async throws {
        let store = MemoryEventStore()
        let policyEngine = PolicyEngine.shared
        let processAdapter = DefaultProcessAdapter(policyEngine: policyEngine)
        let commandRouter = CommandRouter(
            automationHost: nil,
            workspaceRunner: WorkspaceRunner(processAdapter: processAdapter),
            repositoryIndexer: RepositoryIndexer(processAdapter: processAdapter)
        )
        let executor = VerifiedExecutor(
            policyEngine: policyEngine,
            commandRouter: commandRouter,
            preconditionsValidator: PreconditionsValidator(),
            postconditionsValidator: PostconditionsValidator()
        )
        
        let action = UIAction(name: "clickElement", app: "Browser", domID: "login-btn")
        let payload = CommandPayload.ui(action)
        let command = Command(type: .ui, payload: payload, metadata: CommandMetadata(intentID: UUID()))
        
        let result = try await executor.execute(command)
        XCTAssertNotNil(result)
    }
    
    func testNoShellPayloadExists() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        guard let enumerator = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            XCTFail("Could not enumerate Sources directory")
            return
        }

        var foundShell = false
        var offenders = [String]()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if content.contains("case .shell") || content.contains("case shell(") {
                foundShell = true
                offenders.append(fileURL.lastPathComponent)
            }
        }
        XCTAssertFalse(foundShell, "Found legacy '.shell' payload in files: \(offenders.joined(separator: ", "))")
    }

    func testAllProcessUsageRouted() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        guard let enumerator = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            XCTFail("Could not enumerate Sources directory")
            return
        }

        var processUsages = [String]()

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                if (line.contains("Process()") || line.contains("Process.run") || line.contains("Process {")) && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    if !fileURL.lastPathComponent.contains("DefaultProcessAdapter") && !fileURL.lastPathComponent.contains("ProcessShadow") {
                        processUsages.append("\(fileURL.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(processUsages.isEmpty, "Found direct Process usage outside DefaultProcessAdapter in: \n\(processUsages.joined(separator: "\n"))")
    }

    func testNoLegacyPlannersOrExperimentalMemoryExist() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        guard let enumerator = FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            XCTFail("Could not enumerate Sources directory")
            return
        }

        var badFiles = [String]()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let name = fileURL.lastPathComponent
            if name.contains("PlannerFacade") || name.contains("ExperimentalMemory") || name.contains("LegacyPlanner") {
                badFiles.append(name)
            }
        }
        XCTAssertTrue(badFiles.isEmpty, "Found legacy planners or experimental memory paths: \(badFiles.joined(separator: ", "))")
    }
}
