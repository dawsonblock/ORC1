import XCTest
@testable import OracleOS

// MARK: - JSONValue

final class JSONValueTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Roundtrip

    func testRoundtrip_null() throws {
        let v = JSONValue.null
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testRoundtrip_bool() throws {
        for b in [true, false] {
            let v = JSONValue.bool(b)
            let data = try encoder.encode(v)
            let decoded = try decoder.decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, v)
        }
    }

    func testRoundtrip_int() throws {
        let v = JSONValue.int(42)
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testRoundtrip_double() throws {
        let v = JSONValue.double(3.14)
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testRoundtrip_string() throws {
        let v = JSONValue.string("hello")
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testRoundtrip_array() throws {
        let v = JSONValue.array([.int(1), .string("x"), .null])
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testRoundtrip_nestedObject() throws {
        let v = JSONValue.object([
            "flag": .bool(true),
            "count": .int(7),
            "nested": .object(["key": .string("val")])
        ])
        let data = try encoder.encode(v)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    // MARK: Accessors

    func testStringValueAccessor() {
        XCTAssertEqual(JSONValue.string("abc").stringValue, "abc")
        XCTAssertNil(JSONValue.int(1).stringValue)
    }

    func testIntValueAccessor_fromInt() {
        XCTAssertEqual(JSONValue.int(99).intValue, 99)
    }

    func testIntValueAccessor_fromDouble() {
        XCTAssertEqual(JSONValue.double(5.0).intValue, 5)
    }

    func testBoolValueAccessor() {
        XCTAssertEqual(JSONValue.bool(true).boolValue, true)
        XCTAssertNil(JSONValue.string("true").boolValue)
    }

    func testSubscript_objectKey() {
        let v = JSONValue.object(["x": .int(10)])
        XCTAssertEqual(v["x"], .int(10))
        XCTAssertNil(v["missing"])
    }

    func testSubscript_arrayIndex() {
        let v = JSONValue.array([.string("a"), .string("b")])
        XCTAssertEqual(v[0], .string("a"))
        XCTAssertNil(v[99])
    }

    // MARK: Bridge

    func testFromLegacyDict_roundtrip() {
        let dict: [String: Any] = ["name": "oracle", "count": 3, "enabled": true]
        let v = JSONValue.from(legacyDict: dict)
        XCTAssertNotNil(v)
        XCTAssertEqual(v?["name"]?.stringValue, "oracle")
        XCTAssertEqual(v?["count"]?.intValue, 3)
        XCTAssertEqual(v?["enabled"]?.boolValue, true)
    }

    func testFromLegacyDict_nonSerializableReturnsNil() {
        // JSONSerialization.isValidJSONObject rejects dicts containing non-JSON
        // leaf types such as a custom Swift class instance.
        class NotJSON {}
        let dict: [String: Any] = ["bad": NotJSON()]
        XCTAssertNil(JSONValue.from(legacyDict: dict))
    }

    func testToFoundation_preservesTypes() {
        let v = JSONValue.object([
            "num": .int(42),
            "flag": .bool(false),
            "text": .string("hi"),
            "arr": .array([.null])
        ])
        let f = v.toFoundation() as? [String: Any]
        XCTAssertNotNil(f)
        XCTAssertEqual(f?["num"] as? Int, 42)
        XCTAssertEqual(f?["flag"] as? Bool, false)
        XCTAssertEqual(f?["text"] as? String, "hi")
    }
}

// MARK: - MCPToolRequest

final class MCPToolRequestTests: XCTestCase {

    // MARK: Roundtrip via Codable

    func testCodableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let req = MCPToolRequest(
            version: "1",
            name: "oracle_click",
            arguments: .object(["x": .int(100), "y": .int(200)])
        )
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(MCPToolRequest.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.name, "oracle_click")
        XCTAssertEqual(decoded.arguments["x"], .int(100))
        XCTAssertEqual(decoded.arguments["y"], .int(200))
    }

    // MARK: decode(from:) — happy path

    func testDecodeFromLegacyDict_happyPath() {
        let params: [String: Any] = [
            "name": "oracle_type",
            "arguments": ["text": "hello"]
        ]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.name, "oracle_type")
        XCTAssertEqual(req?.string("text"), "hello")
        XCTAssertEqual(req?.version, "1")
    }

    func testDecodeFromLegacyDict_explicitVersion1Accepted() {
        let params: [String: Any] = [
            "version": "1",
            "name": "oracle_scroll",
            "arguments": ["direction": "down"]
        ]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertNotNil(req)
    }

    // MARK: decode(from:) — rejection cases

    func testDecodeFromLegacyDict_missingNameReturnsNil() {
        let params: [String: Any] = ["arguments": ["x": 1]]
        XCTAssertNil(MCPToolRequest.decode(from: params))
    }

    func testDecodeFromLegacyDict_unsupportedVersionReturnsNil() {
        let params: [String: Any] = [
            "version": "99",
            "name": "oracle_click",
            "arguments": [:]
        ]
        XCTAssertNil(MCPToolRequest.decode(from: params))
    }

    func testDecodeFromLegacyDict_emptyArgsProducesEmptyObject() {
        let params: [String: Any] = ["name": "oracle_noop"]
        let req = MCPToolRequest.decode(from: params)
        XCTAssertNotNil(req)
        XCTAssertEqual(req?.arguments, .object([:]))
    }

    // MARK: Argument accessors

    func testArgumentAccessors_string() {
        let req = MCPToolRequest(
            version: "1",
            name: "t",
            arguments: .object(["path": .string("/tmp/file")])
        )
        XCTAssertEqual(req.string("path"), "/tmp/file")
        XCTAssertNil(req.string("missing"))
    }

    func testArgumentAccessors_int() {
        let req = MCPToolRequest(
            version: "1",
            name: "t",
            arguments: .object(["count": .int(5)])
        )
        XCTAssertEqual(req.int("count"), 5)
    }

    func testArgumentAccessors_bool() {
        let req = MCPToolRequest(
            version: "1",
            name: "t",
            arguments: .object(["verbose": .bool(true)])
        )
        XCTAssertEqual(req.bool("verbose"), true)
    }

    func testArgumentAccessors_strings_array() {
        let req = MCPToolRequest(
            version: "1",
            name: "t",
            arguments: .object(["tags": .array([.string("a"), .string("b")])])
        )
        XCTAssertEqual(req.strings("tags"), ["a", "b"])
    }

    func testArgumentAccessors_object() {
        let req = MCPToolRequest(
            version: "1",
            name: "t",
            arguments: .object(["opts": .object(["k": .string("v")])])
        )
        let obj = req.object("opts")
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj?["k"] as? String, "v")
    }
}

// MARK: - MCPToolResponse

final class MCPToolResponseTests: XCTestCase {

    // MARK: Codable roundtrip

    func testCodableRoundtrip_textResponse() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let resp = MCPToolResponse.text("ok")
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(MCPToolResponse.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertFalse(decoded.isError)
        if case .text(let t) = decoded.content.first {
            XCTAssertEqual(t, "ok")
        } else {
            XCTFail("Expected text content")
        }
    }

    func testCodableRoundtrip_errorResponse() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let resp = MCPToolResponse.error("boom")
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(MCPToolResponse.self, from: data)
        XCTAssertTrue(decoded.isError)
    }

    func testCodableRoundtrip_imageAndCaption() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let resp = MCPToolResponse.imageAndCaption(
            base64: "abc123",
            mimeType: "image/png",
            caption: "screenshot"
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(MCPToolResponse.self, from: data)
        XCTAssertFalse(decoded.isError)
        XCTAssertEqual(decoded.content.count, 2)
    }

    // MARK: toLegacyDict

    func testToLegacyDict_textShape() {
        let dict = MCPToolResponse.text("hello").toLegacyDict()
        XCTAssertEqual(dict["isError"] as? Bool, false)
        let content = dict["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 1)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "hello")
    }

    func testToLegacyDict_errorFlag() {
        let dict = MCPToolResponse.error("oops").toLegacyDict()
        XCTAssertEqual(dict["isError"] as? Bool, true)
    }

    func testToLegacyDict_imageShape() {
        let resp = MCPToolResponse.imageAndCaption(
            base64: "data",
            mimeType: "image/jpeg",
            caption: "cap"
        )
        let dict = resp.toLegacyDict()
        let content = dict["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2)
        let imgItem = content?.first(where: { ($0["type"] as? String) == "image" })
        XCTAssertEqual(imgItem?["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(imgItem?["data"] as? String, "data")
    }

    // MARK: MCPContent Codable

    func testMCPContent_textRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let c = MCPContent.text("payload")
        let data = try encoder.encode(c)
        let decoded = try decoder.decode(MCPContent.self, from: data)
        if case .text(let t) = decoded {
            XCTAssertEqual(t, "payload")
        } else {
            XCTFail("Expected text")
        }
    }

    func testMCPContent_imageRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let c = MCPContent.image(base64: "xyz", mimeType: "image/png")
        let data = try encoder.encode(c)
        let decoded = try decoder.decode(MCPContent.self, from: data)
        if case .image(let b64, let mime) = decoded {
            XCTAssertEqual(b64, "xyz")
            XCTAssertEqual(mime, "image/png")
        } else {
            XCTFail("Expected image")
        }
    }

    func testMCPContent_unknownTypeThrows() throws {
        let decoder = JSONDecoder()
        let json = #"{"type":"video","text":"irrelevant"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(MCPContent.self, from: json))
    }
}

// MARK: - MCPVersionError

final class MCPVersionErrorTests: XCTestCase {

    func testMissingVersionDescription() {
        let e = MCPVersionError.missingVersion
        XCTAssert(e.localizedDescription.contains("missing"))
    }

    func testUnsupportedVersionDescription() {
        let e = MCPVersionError.unsupportedVersion("42")
        XCTAssert(e.localizedDescription.contains("42"))
    }
}

// MARK: - VisionContract

final class VisionContractTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: VisionRequest roundtrip

    func testVisionRequest_roundtrip() throws {
        let req = VisionRequest(
            operation: .ocr,
            image: VisionImageInput(filePath: "/tmp/screen.png"),
            parameters: VisionParameters(confidenceThreshold: 0.8, maxResults: 10)
        )
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(VisionRequest.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.operation, .ocr)
        XCTAssertEqual(decoded.image.filePath, "/tmp/screen.png")
        XCTAssertNil(decoded.image.base64Bytes)
        XCTAssertEqual(decoded.parameters?.confidenceThreshold, 0.8)
        XCTAssertEqual(decoded.parameters?.maxResults, 10)
    }

    func testVisionRequest_base64Input_roundtrip() throws {
        let req = VisionRequest(
            operation: .detect,
            image: VisionImageInput(base64Bytes: "abc==")
        )
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(VisionRequest.self, from: data)
        XCTAssertEqual(decoded.image.base64Bytes, "abc==")
        XCTAssertNil(decoded.image.filePath)
    }

    func testVisionRequest_allOperations_codable() throws {
        for op in [VisionOperation.detect, .classify, .ocr, .uiElements] {
            let req = VisionRequest(
                operation: op,
                image: VisionImageInput(artifactID: "art-001")
            )
            let data = try encoder.encode(req)
            let decoded = try decoder.decode(VisionRequest.self, from: data)
            XCTAssertEqual(decoded.operation, op)
        }
    }

    // MARK: VisionImageInput.isValid

    func testImageInput_isValid_oneFieldOnly() {
        XCTAssertTrue(VisionImageInput(filePath: "/x").isValid)
        XCTAssertTrue(VisionImageInput(base64Bytes: "data").isValid)
        XCTAssertTrue(VisionImageInput(artifactID: "id").isValid)
    }

    func testImageInput_isValid_nonePopulated_isFalse() {
        XCTAssertFalse(VisionImageInput().isValid)
    }

    func testImageInput_isValid_twoFields_isFalse() {
        XCTAssertFalse(VisionImageInput(filePath: "/x", base64Bytes: "data").isValid)
    }

    func testImageInput_isValid_allThreeFields_isFalse() {
        XCTAssertFalse(VisionImageInput(filePath: "/x", base64Bytes: "data", artifactID: "id").isValid)
    }

    // MARK: VisionResponse roundtrip

    func testVisionResponse_success_roundtrip() throws {
        let resp = VisionResponse(results: [
            VisionResult(
                label: "button",
                confidence: 0.95,
                boundingBox: VisionRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
                metadata: ["role": "AXButton"]
            )
        ])
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(VisionResponse.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertTrue(decoded.succeeded)
        XCTAssertNil(decoded.error)
        XCTAssertEqual(decoded.results.count, 1)
        XCTAssertEqual(decoded.results[0].label, "button")
        XCTAssertEqual(decoded.results[0].confidence, 0.95)
        XCTAssertEqual(decoded.results[0].boundingBox, VisionRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
        XCTAssertEqual(decoded.results[0].metadata["role"], "AXButton")
    }

    func testVisionResponse_failure_roundtrip() throws {
        let resp = VisionResponse(
            results: [],
            error: VisionError(code: .timeout, detail: "sidecar timed out after 5s")
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(VisionResponse.self, from: data)
        XCTAssertFalse(decoded.succeeded)
        XCTAssertNotNil(decoded.error)
        XCTAssertEqual(decoded.error?.code, .timeout)
    }

    // MARK: VisionError codes all round-trip

    func testVisionErrorCode_allCases_roundtrip() throws {
        let codes: [VisionErrorCode] = [
            .timeout, .modelUnavailable, .invalidInput,
            .partialResult, .unsupportedVersion, .internalError
        ]
        for code in codes {
            let err = VisionError(code: code, detail: "test")
            let data = try encoder.encode(err)
            let decoded = try decoder.decode(VisionError.self, from: data)
            XCTAssertEqual(decoded.code, code)
        }
    }

    // MARK: VisionRect equality

    func testVisionRect_equality() {
        let r1 = VisionRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        let r2 = VisionRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        let r3 = VisionRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)
        XCTAssertEqual(r1, r2)
        XCTAssertNotEqual(r1, r3)
    }

    // MARK: VisionOperation raw values are stable

    func testVisionOperation_rawValues_stable() {
        XCTAssertEqual(VisionOperation.detect.rawValue, "detect")
        XCTAssertEqual(VisionOperation.classify.rawValue, "classify")
        XCTAssertEqual(VisionOperation.ocr.rawValue, "ocr")
        XCTAssertEqual(VisionOperation.uiElements.rawValue, "uiElements")
    }
}

// MARK: - WebContract

final class WebContractTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: WebIntentSubmission roundtrip

    func testWebIntentSubmission_roundtrip() throws {
        let sub = WebIntentSubmission(
            clientID: "client-abc",
            intent: WebIntent(objective: "Run tests", domain: "code"),
            context: WebSubmissionContext(workspaceRoot: "/projects/oracle", activeApp: "Xcode")
        )
        let data = try encoder.encode(sub)
        let decoded = try decoder.decode(WebIntentSubmission.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.clientID, "client-abc")
        XCTAssertEqual(decoded.intent.objective, "Run tests")
        XCTAssertEqual(decoded.intent.domain, "code")
        XCTAssertEqual(decoded.context?.workspaceRoot, "/projects/oracle")
        XCTAssertEqual(decoded.context?.activeApp, "Xcode")
    }

    func testWebIntentSubmission_noContext_roundtrip() throws {
        let sub = WebIntentSubmission(
            clientID: "c",
            intent: WebIntent(objective: "Click button", domain: "ui")
        )
        let data = try encoder.encode(sub)
        let decoded = try decoder.decode(WebIntentSubmission.self, from: data)
        XCTAssertNil(decoded.context)
    }

    func testWebIntentSubmission_metadata_preserved() throws {
        let sub = WebIntentSubmission(
            clientID: "c",
            intent: WebIntent(
                objective: "Build",
                domain: "code",
                metadata: ["branch": "main", "scheme": "Release"]
            )
        )
        let data = try encoder.encode(sub)
        let decoded = try decoder.decode(WebIntentSubmission.self, from: data)
        XCTAssertEqual(decoded.intent.metadata["branch"], "main")
        XCTAssertEqual(decoded.intent.metadata["scheme"], "Release")
    }

    // MARK: WebSubmissionAck roundtrip

    func testWebSubmissionAck_accepted_roundtrip() throws {
        let ack = WebSubmissionAck(
            clientID: "c",
            intentID: "intent-001",
            status: "accepted"
        )
        let data = try encoder.encode(ack)
        let decoded = try decoder.decode(WebSubmissionAck.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.status, "accepted")
        XCTAssertNil(decoded.error)
    }

    func testWebSubmissionAck_rejected_roundtrip() throws {
        let ack = WebSubmissionAck(
            clientID: "c",
            intentID: "intent-002",
            status: "error",
            error: WebError(code: .intentRejected, detail: "policy blocked")
        )
        let data = try encoder.encode(ack)
        let decoded = try decoder.decode(WebSubmissionAck.self, from: data)
        XCTAssertEqual(decoded.error?.code, .intentRejected)
    }

    // MARK: WebEvent roundtrip

    func testWebEvent_roundtrip_withJSONValuePayload() throws {
        let event = WebEvent(
            type: WebEventType.runStartedV1,
            correlationID: "intent-001",
            timestamp: "2024-01-01T00:00:00Z",
            payload: .object(["step": .int(1), "tool": .string("xcodebuild")])
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(WebEvent.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.type, WebEventType.runStartedV1)
        XCTAssertEqual(decoded.correlationID, "intent-001")
        XCTAssertEqual(decoded.payload["step"], .int(1))
        XCTAssertEqual(decoded.payload["tool"], .string("xcodebuild"))
    }

    func testWebEvent_nullPayload_roundtrip() throws {
        let event = WebEvent(
            type: WebEventType.runCompletedV1,
            correlationID: "c",
            timestamp: "2024-01-01T00:00:00Z",
            payload: .null
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(WebEvent.self, from: data)
        XCTAssertEqual(decoded.payload, .null)
    }

    // MARK: WebEventType — string stability

    func testWebEventType_strings_stable() {
        // These string values appear in wire-level logs and must never change.
        XCTAssertEqual(WebEventType.runStartedV1, "run.started.v1")
        XCTAssertEqual(WebEventType.runCompletedV1, "run.completed.v1")
        XCTAssertEqual(WebEventType.runFailedV1, "run.failed.v1")
        XCTAssertEqual(WebEventType.stepCompletedV1, "step.completed.v1")
        XCTAssertEqual(WebEventType.stepFailedV1, "step.failed.v1")
        XCTAssertEqual(WebEventType.artifactAvailableV1, "artifact.available.v1")
        XCTAssertEqual(WebEventType.policyBlockedV1, "policy.blocked.v1")
        XCTAssertEqual(WebEventType.approvalRequiredV1, "approval.required.v1")
    }

    // MARK: ArtifactFetchRequest / ArtifactFetchResponse roundtrip

    func testArtifactFetchRequest_roundtrip() throws {
        let req = ArtifactFetchRequest(artifactID: "art-xyz", kind: .screenshot)
        let data = try encoder.encode(req)
        let decoded = try decoder.decode(ArtifactFetchRequest.self, from: data)
        XCTAssertEqual(decoded.version, "1")
        XCTAssertEqual(decoded.artifactID, "art-xyz")
        XCTAssertEqual(decoded.kind, .screenshot)
    }

    func testArtifactFetchResponse_success_roundtrip() throws {
        let resp = ArtifactFetchResponse(
            artifactID: "art-xyz",
            kind: .log,
            base64Contents: "bG9n",
            mimeType: "text/plain"
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(ArtifactFetchResponse.self, from: data)
        XCTAssertTrue(decoded.succeeded)
        XCTAssertEqual(decoded.base64Contents, "bG9n")
        XCTAssertEqual(decoded.mimeType, "text/plain")
        XCTAssertNil(decoded.error)
    }

    func testArtifactFetchResponse_failure_roundtrip() throws {
        let resp = ArtifactFetchResponse(
            artifactID: "art-missing",
            kind: .patch,
            error: WebError(code: .artifactNotFound, detail: "no such artifact")
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(ArtifactFetchResponse.self, from: data)
        XCTAssertFalse(decoded.succeeded)
        XCTAssertEqual(decoded.error?.code, .artifactNotFound)
    }

    // MARK: ArtifactKind raw values are stable

    func testArtifactKind_rawValues_stable() {
        XCTAssertEqual(ArtifactKind.log.rawValue, "log")
        XCTAssertEqual(ArtifactKind.patch.rawValue, "patch")
        XCTAssertEqual(ArtifactKind.diagnostic.rawValue, "diagnostic")
        XCTAssertEqual(ArtifactKind.file.rawValue, "file")
        XCTAssertEqual(ArtifactKind.screenshot.rawValue, "screenshot")
        XCTAssertEqual(ArtifactKind.trace.rawValue, "trace")
    }

    // MARK: WebError / WebErrorCode

    func testWebErrorCode_allCases_roundtrip() throws {
        let codes: [WebErrorCode] = [
            .unsupportedVersion, .invalidPayload, .intentRejected,
            .artifactNotFound, .timeout, .internalError
        ]
        for code in codes {
            let err = WebError(code: code, detail: "test")
            let data = try encoder.encode(err)
            let decoded = try decoder.decode(WebError.self, from: data)
            XCTAssertEqual(decoded.code, code)
        }
    }

    // MARK: Version mismatch detection

    func testWebIntentSubmission_unexpectedVersion_preserved() throws {
        // The type stores version as a plain String; consumers are responsible
        // for rejecting unknown versions at intake.  This test confirms the
        // version value survives the encode/decode cycle unchanged.
        let json = """
        {
          "version": "99",
          "clientID": "c",
          "intent": { "objective": "x", "domain": "ui", "metadata": {} }
        }
        """.data(using: .utf8)!
        let decoded = try decoder.decode(WebIntentSubmission.self, from: json)
        XCTAssertEqual(decoded.version, "99",
            "Unknown version must survive decode so the intake layer can reject it explicitly")
    }

    func testArtifactFetchRequest_unexpectedVersion_preserved() throws {
        let json = """
        {"version":"7","artifactID":"x","kind":"log"}
        """.data(using: .utf8)!
        let decoded = try decoder.decode(ArtifactFetchRequest.self, from: json)
        XCTAssertEqual(decoded.version, "7")
    }
}
