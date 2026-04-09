import Foundation

struct ClaudeConfig: Codable, Equatable {
    var mcpServers: [String: ClaudeMCPServerEntry]
    var allowedTools: [String]?
    var additionalFields: [String: JSONValue]

    init(
        mcpServers: [String: ClaudeMCPServerEntry] = [:],
        allowedTools: [String]? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.mcpServers = mcpServers
        self.allowedTools = allowedTools
        self.additionalFields = additionalFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        mcpServers = try container.decodeIfPresent([String: ClaudeMCPServerEntry].self, forKey: .named("mcpServers")) ?? [:]
        allowedTools = try container.decodeIfPresent([String].self, forKey: .named("allowedTools"))

        let reserved = Set(["mcpServers", "allowedTools"])
        additionalFields = try container.allKeys.reduce(into: [:]) { partialResult, key in
            guard !reserved.contains(key.stringValue) else { return }
            partialResult[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        if !mcpServers.isEmpty {
            try container.encode(mcpServers, forKey: .named("mcpServers"))
        }
        if let allowedTools {
            try container.encode(allowedTools, forKey: .named("allowedTools"))
        }
        for (key, value) in additionalFields {
            try container.encode(value, forKey: .named(key))
        }
    }

    static func load(from url: URL) throws -> ClaudeConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ClaudeConfig()
        }
        let data = try Data(contentsOf: url)
        return try OracleJSONCoding.makeDecoder().decode(ClaudeConfig.self, from: data)
    }

    func encodedData() throws -> Data {
        try OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys]).encode(self)
    }
}

struct ClaudeMCPServerEntry: Codable, Equatable {
    var command: String
    var args: [String]
    var env: [String: JSONValue]
    var trust: Bool?
    var additionalFields: [String: JSONValue]

    init(
        command: String,
        args: [String],
        env: [String: JSONValue] = [:],
        trust: Bool? = nil,
        additionalFields: [String: JSONValue] = [:]
    ) {
        self.command = command
        self.args = args
        self.env = env
        self.trust = trust
        self.additionalFields = additionalFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        command = try container.decode(String.self, forKey: .named("command"))
        args = try container.decodeIfPresent([String].self, forKey: .named("args")) ?? []
        env = try container.decodeIfPresent([String: JSONValue].self, forKey: .named("env")) ?? [:]
        trust = try container.decodeIfPresent(Bool.self, forKey: .named("trust"))

        let reserved = Set(["command", "args", "env", "trust"])
        additionalFields = try container.allKeys.reduce(into: [:]) { partialResult, key in
            guard !reserved.contains(key.stringValue) else { return }
            partialResult[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(command, forKey: .named("command"))
        try container.encode(args, forKey: .named("args"))
        try container.encode(env, forKey: .named("env"))
        try container.encodeIfPresent(trust, forKey: .named("trust"))
        for (key, value) in additionalFields {
            try container.encode(value, forKey: .named(key))
        }
    }
}

private struct DynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    static func named(_ value: String) -> DynamicCodingKey {
        DynamicCodingKey(stringValue: value)!
    }
}
