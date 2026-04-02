import os

file_path = "Tests/OracleOSTests/Governance/ExecutionBoundaryTests.swift"
with open(file_path, "r") as f:
    content = f.read()

new_tests = r"""
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
                    if !fileURL.lastPathComponent.contains("DefaultProcessAdapter") {
                        processUsages.append("\(fileURL.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertTrue(processUsages.isEmpty, "Found direct Process usage outside DefaultProcessAdapter in: \n\(processUsages.joined(separator: "\n"))")
    }
}
"""

if "testNoShellPayloadExists" not in content:
    content = content.replace("}", new_tests)
    with open(file_path, "w") as f:
        f.write(content)
