// MCPBoundary.swift
// Typed contract layer for the MCP server boundary.
//
// All data entering or leaving the typed MCP runtime path must pass through these
// types. Legacy `[String: Any]` transport is confined to the outer JSON-RPC
// adapter seam (`MCPDispatch.handle(_ params:)` and legacy export helpers).
//
// Responses always carry an explicit version. The legacy JSON-RPC request adapter
// still defaults omitted request versions to "1" for compatibility at the outer seam.

import Foundation

/// Shared export seam for MCP typed payloads.
///
/// This is the single helper used to convert internal `Encodable` payloads into
/// legacy dictionary transport at the outer compatibility boundary.
func mcpLegacyJSONObject<T: Encodable>(from value: T) -> [String: Any]? {
    let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.sortedKeys])
    guard let data = try? encoder.encode(value),
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any]
    else {
        return nil
    }
    return dictionary
}

// MARK: - JSONValue

/// Closed, Sendable, Codable value type for dynamic MCP arguments and results.
/// Replaces `[String: Any]` inside the typed MCP runtime path.
public enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    // MARK: Bridging from legacy Foundation values

    /// Convert a JSON-safe Foundation value to JSONValue.
    /// Accepts dictionaries, arrays, strings, numbers, booleans, and NSNull.
    /// Fails and returns nil for non-JSON-serializable values.
    /// Note: numeric values are canonicalized through JSON round-trip — a Foundation
    /// Double such as 1.0 may decode as `.int(1)` due to the decoder's Int-first strategy.
    public static func from(legacyValue value: Any) -> JSONValue? {
        let wrapped: [String: Any] = ["value": value]
        guard JSONSerialization.isValidJSONObject(wrapped),
            let data = try? JSONSerialization.data(withJSONObject: wrapped),
            let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data),
            let jsonValue = decoded["value"]
        else { return nil }
        return jsonValue
    }

    /// Convert a JSON-safe [String: Any] dictionary to JSONValue.
    /// Subject to the same numeric canonicalization as `from(legacyValue:)`.
    /// Fails and returns nil for non-JSON-serializable values.
    public static func from(legacyDict dict: [String: Any]) -> JSONValue? {
        from(legacyValue: dict)
    }

    /// Convert JSONValue back to a Foundation object for legacy outer-edge APIs only.
    public func toFoundation() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toFoundation() }
        case .object(let v): return v.mapValues { $0.toFoundation() }
        }
    }

    // MARK: Accessors

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var intValue: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Array accessor. Returns the underlying array if this value is an array, otherwise nil.
    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Object accessor. Returns the underlying dictionary if this value is an object, otherwise nil.
    public var objectValue: [String: JSONValue]? {
        if case .object(let obj) = self { return obj }
        return nil
    }
    public subscript(_ key: String) -> JSONValue? {
        if case .object(let d) = self { return d[key] }
        return nil
    }
    public subscript(_ index: Int) -> JSONValue? {
        if case .array(let a) = self, index < a.count { return a[index] }
        return nil
    }
}

// MARK: - MCP Tool Request

/// Typed, Sendable representation of an incoming MCP tools/call payload.
/// Version field is mandatory. Unknown versions are rejected immediately.
public struct MCPToolRequest: Sendable, Codable {
    /// Wire version. Current supported value: "1".
    public let version: String
    /// Tool name (e.g. "oracle_click").
    public let name: String
    /// Typed arguments. Empty object if no arguments provided.
    public let arguments: JSONValue

    public init(version: String, name: String, arguments: JSONValue) {
        self.version = version
        self.name = name
        self.arguments = arguments
    }

    /// Decode from the raw `[String: Any]` params dict that the JSON-RPC server
    /// passes in. This is the sole legacy request adapter seam.
    /// Returns a typed `Result` so callers can surface specific failure reasons
    /// (missing name, unsupported version, or non-JSON-serializable arguments).
    public static func decodeResult(from params: [String: Any]) -> Result<
        MCPToolRequest, MCPDecodeFailure
    > {
        guard let name = params["name"] as? String else { return .failure(.missingName) }

        // Version is conveyed at the transport layer; default to "1" for callers
        // that predate explicit versioning.
        let version = params["version"] as? String ?? "1"
        guard version == "1" else { return .failure(.unsupportedVersion(version)) }

        let arguments: JSONValue
        if let rawArgs = params["arguments"] {
            guard let decoded = JSONValue.from(legacyValue: rawArgs) else {
                return .failure(.invalidArguments)
            }
            arguments = decoded
        } else {
            arguments = .object([:])
        }

        return .success(MCPToolRequest(version: version, name: name, arguments: arguments))
    }

    /// Convenience wrapper around `decodeResult(from:)`.
    /// Returns nil on any failure; prefer `decodeResult(from:)` where the failure
    /// reason matters for error reporting.
    public static func decode(from params: [String: Any]) -> MCPToolRequest? {
        try? decodeResult(from: params).get()
    }

    // MARK: Argument helpers (typed extraction from JSONValue arguments)

    public func string(_ key: String) -> String? { arguments[key]?.stringValue }
    public func int(_ key: String) -> Int? { arguments[key]?.intValue }
    public func double(_ key: String) -> Double? { arguments[key]?.doubleValue }
    public func bool(_ key: String) -> Bool? { arguments[key]?.boolValue }
    public func strings(_ key: String) -> [String]? {
        guard case .array(let arr) = arguments[key] else { return nil }
        return arr.compactMap { $0.stringValue }
    }
    public func array(_ key: String) -> [JSONValue]? {
        arguments[key]?.arrayValue
    }

    public func object(_ key: String) -> [String: Any]? {
        objectValue(key)?.mapValues { $0.toFoundation() }
    }

    public func objectValue(_ key: String) -> [String: JSONValue]? {
        arguments[key]?.objectValue
    }

    public func value(_ key: String) -> JSONValue? {
        arguments[key]
    }
}

// MARK: - MCP Tool Response

/// Typed, Sendable MCP response envelope.
/// All tool results are expressed through this type at the boundary.
public struct MCPToolResponse: Sendable, Codable {
    /// Wire version. Always "1".
    public let version: String
    /// MCP content array (text, image, etc.).
    public let content: [MCPContent]
    /// True when the tool result represents an error.
    public let isError: Bool

    public init(version: String = "1", content: [MCPContent], isError: Bool) {
        self.version = version
        self.content = content
        self.isError = isError
    }

    // MARK: Convenience constructors

    public static func text(_ text: String, isError: Bool = false) -> MCPToolResponse {
        MCPToolResponse(content: [.text(text)], isError: isError)
    }

    public static func error(_ message: String) -> MCPToolResponse {
        MCPToolResponse(content: [.text(message)], isError: true)
    }

    public static func imageAndCaption(base64: String, mimeType: String, caption: String)
        -> MCPToolResponse
    {
        MCPToolResponse(
            content: [.image(base64: base64, mimeType: mimeType), .text(caption)],
            isError: false
        )
    }

    /// Convert to the legacy [String: Any] wire format that the JSON-RPC layer expects.
    public func toLegacyDict() -> [String: Any] {
        [
            "content": content.map { $0.toLegacyDict() },
            "isError": isError,
        ]
    }
}

// MARK: - MCP Content

/// A single content item in an MCP response.
public enum MCPContent: Sendable, Codable {
    case text(String)
    case image(base64: String, mimeType: String)

    public func toLegacyDict() -> [String: Any] {
        switch self {
        case .text(let t):
            return ["type": "text", "text": t]
        case .image(let b64, let mime):
            return ["type": "image", "data": b64, "mimeType": mime]
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "image":
            self = .image(
                base64: try c.decode(String.self, forKey: .data),
                mimeType: try c.decode(String.self, forKey: .mimeType)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown MCPContent type: \(type_)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .image(let b64, let mime):
            try c.encode("image", forKey: .type)
            try c.encode(b64, forKey: .data)
            try c.encode(mime, forKey: .mimeType)
        }
    }
}

// MARK: - Decode Failure

/// Typed failure reason returned by `MCPToolRequest.decodeResult(from:)`.
public enum MCPDecodeFailure: Error, Sendable, Equatable {
    /// The `name` field is absent or not a String.
    case missingName
    /// The `version` field is present but not supported by this runtime.
    case unsupportedVersion(String)
    /// The `arguments` field is present but cannot be bridged to `JSONValue`
    /// (e.g., it contains a non-JSON-serializable Foundation object).
    case invalidArguments

    public var localizedDescription: String {
        switch self {
        case .missingName:
            return "MCP request is missing required field \"name\"."
        case .unsupportedVersion(let v):
            return "MCP request version \"\(v)\" is not supported. Expected version \"1\"."
        case .invalidArguments:
            return "MCP request \"arguments\" field is not JSON-serializable."
        }
    }
}

// MARK: - Version Error

/// Error returned when the version field is missing or unsupported.
public enum MCPVersionError: Error, Sendable {
    case missingVersion
    case unsupportedVersion(String)

    public var localizedDescription: String {
        switch self {
        case .missingVersion:
            return "MCP request is missing a version field. Expected version \"1\"."
        case .unsupportedVersion(let v):
            return "MCP request version \"\(v)\" is not supported. Expected version \"1\"."
        }
    }
}
