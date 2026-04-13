import Foundation
import Testing

@testable import OracleOS

@Suite("Vision Perception Contract")
struct VisionPerceptionContractTests {

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Helpers

    private func validFrame(
        overallConfidence: Double = 0.85,
        detections: [VisionDetection]? = nil
    ) -> VisionPerceptionFrame {
        let ts = ISO8601DateFormatter().string(from: Date())
        let dets =
            detections ?? [
                VisionDetection(
                    id: "btn1", elementType: "button",
                    frame: VisionFrame(x: 100, y: 200, width: 80, height: 30),
                    confidence: 0.92, text: "Submit", source: "yolo", timestamp: ts
                )
            ]
        return VisionPerceptionFrame(
            detections: dets,
            overallConfidence: overallConfidence,
            timestamp: ts,
            screenWidth: 1728,
            screenHeight: 1117
        )
    }

    // MARK: - Valid Frames

    @Test("Valid frame passes validation")
    func validFramePasses() {
        let violations = VisionContractValidator.validate(validFrame())
        #expect(violations.isEmpty)
    }

    // MARK: - Confidence

    @Test("Low overall confidence produces violation")
    func lowConfidence() {
        let violations = VisionContractValidator.validate(validFrame(overallConfidence: 0.1))
        #expect(violations.contains(where: { $0.contains("below minimum") }))
    }

    // MARK: - Empty Detections

    @Test("Empty detections produce violation")
    func emptyDetections() {
        let frame = validFrame(detections: [])
        let violations = VisionContractValidator.validate(frame)
        #expect(violations.contains(where: { $0.contains("no detections") }))
    }

    // MARK: - Detection Quality

    @Test("Detection with negative confidence produces violation")
    func negativeDetectionConfidence() {
        let ts = ISO8601DateFormatter().string(from: Date())
        let bad = VisionDetection(
            id: "x", elementType: "button",
            frame: VisionFrame(x: 0, y: 0, width: 10, height: 10),
            confidence: -0.5, source: "test", timestamp: ts
        )
        let frame = validFrame(detections: [bad])
        let violations = VisionContractValidator.validate(frame)
        #expect(violations.contains(where: { $0.contains("out-of-range confidence") }))
    }

    @Test("Detection with zero-size frame produces violation")
    func zeroSizeFrame() {
        let ts = ISO8601DateFormatter().string(from: Date())
        let bad = VisionDetection(
            id: "y", elementType: "icon",
            frame: VisionFrame(x: 0, y: 0, width: 0, height: 10),
            confidence: 0.8, source: "test", timestamp: ts
        )
        let frame = validFrame(detections: [bad])
        let violations = VisionContractValidator.validate(frame)
        #expect(violations.contains(where: { $0.contains("non-positive dimensions") }))
    }

    @Test("Detection with empty elementType produces violation")
    func emptyElementType() {
        let ts = ISO8601DateFormatter().string(from: Date())
        let bad = VisionDetection(
            id: "z", elementType: "",
            frame: VisionFrame(x: 0, y: 0, width: 10, height: 10),
            confidence: 0.8, source: "test", timestamp: ts
        )
        let frame = validFrame(detections: [bad])
        let violations = VisionContractValidator.validate(frame)
        #expect(violations.contains(where: { $0.contains("empty elementType") }))
    }

    // MARK: - Freshness

    @Test("Stale frame produces violation")
    func staleFrame() {
        let oldTs = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let frame = VisionPerceptionFrame(
            detections: [
                VisionDetection(
                    id: "a", elementType: "button",
                    frame: VisionFrame(x: 0, y: 0, width: 10, height: 10),
                    confidence: 0.9, source: "test", timestamp: oldTs
                )
            ],
            overallConfidence: 0.9,
            timestamp: oldTs,
            screenWidth: 1728,
            screenHeight: 1117
        )
        let violations = VisionContractValidator.validate(frame)
        #expect(violations.contains(where: { $0.contains("old") }))
    }

    @Test("Future frame produces violation")
    func futureFrame() {
        let futureTs = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))
        let frame = VisionPerceptionFrame(
            detections: [
                VisionDetection(
                    id: "future", elementType: "button",
                    frame: VisionFrame(x: 0, y: 0, width: 10, height: 10),
                    confidence: 0.9, source: "test", timestamp: futureTs
                )
            ],
            overallConfidence: 0.9,
            timestamp: futureTs,
            screenWidth: 1728,
            screenHeight: 1117
        )

        let violations = VisionContractValidator.validate(frame)

        #expect(violations.contains(where: { $0.contains("in the future") }))
    }

    // MARK: - Codable Round Trip

    @Test("VisionDetection encodes and decodes correctly")
    func codableRoundTrip() throws {
        let ts = ISO8601DateFormatter().string(from: Date())
        let original = VisionDetection(
            id: "btn", elementType: "button",
            frame: VisionFrame(x: 10, y: 20, width: 30, height: 40),
            confidence: 0.95, text: "OK", source: "yolo", timestamp: ts
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VisionDetection.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.frame.centerX == 25)
    }

    @Test("Ground schema includes optional Swift response fields")
    func groundSchemaIncludesSwiftOptionalFields() throws {
        let schema = try read("vision-sidecar/schema/endpoints.py")

        #expect(schema.contains("\"confidence\": (float, type(None))"))
        #expect(schema.contains("\"raw\": (str, type(None))"))
        #expect(schema.contains("\"inference_ms\": (int, type(None))"))
    }

    @Test("Parse schema includes sidecar context field")
    func parseSchemaIncludesContext() throws {
        let schema = try read("vision-sidecar/schema/endpoints.py")

        #expect(schema.contains("\"context\": (str, type(None))"))
    }
}
