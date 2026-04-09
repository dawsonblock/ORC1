import Foundation
import Testing
@testable import OracleOS

@Suite("Claude Config Round Trip")
struct ClaudeConfigRoundTripTests {
    @Test("Config updates preserve unknown root and server fields")
    func preservesUnknownFields() throws {
        let config = ClaudeConfig(
            mcpServers: [
                "oracle-os": ClaudeMCPServerEntry(
                    command: "/usr/local/bin/oracle",
                    args: ["mcp"],
                    env: ["MODE": .string("local")],
                    trust: false,
                    additionalFields: ["type": .string("stdio")]
                ),
            ],
            allowedTools: ["mcp__oracle-os__*"],
            additionalFields: ["theme": .string("dark")]
        )

        let data = try OracleJSONCoding.makeEncoder(outputFormatting: [.sortedKeys]).encode(config)
        let decoded = try OracleJSONCoding.makeDecoder().decode(ClaudeConfig.self, from: data)

        #expect(decoded.additionalFields["theme"] == .string("dark"))
        #expect(decoded.mcpServers["oracle-os"]?.additionalFields["type"] == .string("stdio"))
        #expect(decoded.allowedTools == ["mcp__oracle-os__*"])
    }
}
