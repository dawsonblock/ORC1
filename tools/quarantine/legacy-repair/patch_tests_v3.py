import re

files = {
    "Tests/OracleOSTests/Governance/RuntimeInvariantTests.swift": """
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

    func test_runtime_sources_do_not_shell_out() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else { return }

        let forbidden = ["/bin/zsh", "/bin/bash", "\\"-c\\"", "[\\"-c\\",", "Process()"]
        let allowlist = ["DefaultProcessAdapter.swift", "WorkspaceRunner.swift", "RuntimeBootstrap.swift", "ProcessAdapter.swift", "HostInspectionAdapter.swift", "BrowserAdapter.swift"]
        var offenders: [String] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let fileName = fileURL.lastPathComponent
            if allowlist.contains(fileName) { continue }
            if fileURL.path.contains("/Experimental/") || fileURL.path.contains("/Intelligence/") { continue }

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for pattern in forbidden {
                if text.contains(pattern) { offenders.append(fileName) }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Forbidden shell references: \\(offenders)")
    }

    func test_default_process_adapter_not_constructed_outside_execution_wiring() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else { return }
        
        let allowlist = ["DefaultProcessAdapter.swift", "RuntimeBootstrap.swift"]
        var offenders: [String] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let fileName = fileURL.lastPathComponent
            if allowlist.contains(fileName) { continue }
            if fileURL.path.contains("/Experimental/") || fileURL.path.contains("/Intelligence/") { continue }
            
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if text.contains("DefaultProcessAdapter(") { offenders.append(fileName) }
        }
        XCTAssertTrue(offenders.isEmpty, "DefaultProcessAdapter constructed outside wiring: \\(offenders)")
    }

    func test_planner_calls_only_live_in_runtime_orchestrator() throws {
        let sourcesRoot = repositoryRoot().appendingPathComponent("Sources/OracleOS", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else { return }

        let allowlist = ["RuntimeOrchestrator.swift", "SystemRouter.swift", "AgentLoop+Run.swift"]
        var offenders: [String] = []

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let fileName = fileURL.lastPathComponent
            if allowlist.contains(fileName) { continue }

            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if text.contains("planner.plan(") || text.contains("planner.nextStep(") { offenders.append(fileName) }
        }
        XCTAssertTrue(offenders.isEmpty, "planner.plan called outside Orchestrator: \\(offenders)")
    }

    func test_supported_command_payload_cases_only() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/Core/Command/Command.swift")
        guard let text = try? String(contentsOf: sourcePath, encoding: .utf8) else { return }

        let forbidden = ["diagnostic(", "envSetup(", "hostService(", "inference("]
        for pattern in forbidden {
            XCTAssertFalse(text.contains(pattern), "Command.swift has: \\(pattern)")
        }
    }
""",
    
    "Tests/OracleOSTests/Governance/ControllerBoundaryTests.swift": """
    func test_code_intents_do_not_emit_ui_payloads() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/Planning/MainPlanner+Planner.swift")
        guard let text = try? String(contentsOf: sourcePath, encoding: .utf8) else { return }
        XCTAssertFalse(text.contains("type: .code") && text.contains("payload: .ui("), "MainPlanner emits .ui for .code")
    }
""",
    
    "Tests/OracleOSTests/Governance/TransitionalArtifactRemovalTests.swift": """
    func test_system_router_does_not_directly_spawn_processes() throws {
        let sourcePath = repositoryRoot().appendingPathComponent("Sources/OracleOS/Execution/Routing/SystemRouter.swift")
        guard let text = try? String(contentsOf: sourcePath, encoding: .utf8) else { return }
        
        let forbidden = ["DefaultProcessAdapter(", "/bin/zsh", "/bin/bash", "\\"-c\\"", "Process("]
        for pattern in forbidden {
            XCTAssertFalse(text.contains(pattern), "SystemRouter contains \\(pattern)")
        }
    }
"""
}

for filepath, new_tests in files.items():
    with open(filepath, "r") as f:
        content = f.read()
    
    content = re.sub(r"}\s*$", new_tests + "\n}\n", content)
    
    with open(filepath, "w") as f:
        f.write(content)
