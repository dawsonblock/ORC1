import Foundation
import OracleOS

private struct ClaudeDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ClaudeMCPServerEntry: Sendable, Equatable {
    var type: String
    var command: String
    var args: [String]
    var additionalFields: [String: JSONValue]

    init(
        type: String,
        command: String,
        args: [String],
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.type = type
        self.command = command
        self.args = args
        self.additionalFields = additionalFields
    }

    static func fromJSONValue(_ value: JSONValue?) -> ClaudeMCPServerEntry? {
        guard let object = value?.objectValue,
              let type = object["type"]?.stringValue,
              let command = object["command"]?.stringValue else {
            return nil
        }
        let args = object["args"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        var additional = object
        additional.removeValue(forKey: "type")
        additional.removeValue(forKey: "command")
        additional.removeValue(forKey: "args")

        return ClaudeMCPServerEntry(
            type: type,
            command: command,
            args: args,
            additionalFields: additional
        )
    }

    func toJSONValue() -> JSONValue {
        var object = additionalFields
        object["type"] = .string(type)
        object["command"] = .string(command)
        object["args"] = .array(args.map(JSONValue.string))
        return .object(object)
    }
}

struct ClaudeConfigFile: Sendable, Equatable {
    static let defaultServerName = "oracle-os"

    var root: [String: JSONValue]

    init(root: [String: JSONValue] = [:]) {
        self.root = root
    }

    var mcpServers: [String: ClaudeMCPServerEntry] {
        guard let object = root["mcpServers"]?.objectValue else {
            return [:]
        }
        return object.reduce(into: [String: ClaudeMCPServerEntry]()) { partialResult, entry in
            if let server = ClaudeMCPServerEntry.fromJSONValue(entry.value) {
                partialResult[entry.key] = server
            }
        }
    }

    var allowedTools: [String] {
        root["allowedTools"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    mutating func setServer(name: String, entry: ClaudeMCPServerEntry) {
        var servers = root["mcpServers"]?.objectValue ?? [:]
        servers[name] = entry.toJSONValue()
        root["mcpServers"] = .object(servers)
    }

    mutating func ensureAllowedTool(_ tool: String) {
        var tools = allowedTools
        guard !tools.contains(tool) else { return }
        tools.append(tool)
        root["allowedTools"] = .array(tools.map(JSONValue.string))
    }

    func server(named name: String) -> ClaudeMCPServerEntry? {
        mcpServers[name]
    }

    static func load(from path: String) -> ClaudeConfigFile? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        let decoder = JSONDecoder()
        guard let root = try? decoder.decode([String: JSONValue].self, from: data) else {
            return nil
        }
        return ClaudeConfigFile(root: root)
    }

    func write(to path: String) throws {
        let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let data = try encoder.encode(root)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
