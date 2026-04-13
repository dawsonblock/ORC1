import Foundation
import Testing

@testable import OracleOS

@MainActor
@Suite("Vision Scanner")
struct VisionScannerTests {

    @Test("Crop box validation rejects malformed payloads")
    func validateCropBoxRejectsMalformedPayloads() {
        #expect(VisionScanner.validateCropBox(nil) == nil)
        #expect(
            VisionScanner.validateCropBox([0, 10, 20])
                == "crop_box must contain exactly four coordinates"
        )
        #expect(
            VisionScanner.validateCropBox([10, 10, 10, 50])
                == "crop_box must satisfy x2>x1 and y2>y1"
        )
    }

    @Test("Grounding context prefers display dimensions for effectively fullscreen captures")
    func groundingContextUsesDisplayDimensionsForFullscreenWindows() {
        let context = VisionScanner.groundingContext(
            screenshotWidth: 1512,
            screenshotHeight: 982,
            windowWidth: 1700,
            windowHeight: 1000,
            windowX: 50,
            windowY: 60,
            displayWidth: 1728,
            displayHeight: 1117
        )

        #expect(context.sidecarWidth == 1728)
        #expect(context.sidecarHeight == 1117)
        #expect(context.offsetX == 0)
        #expect(context.offsetY == 0)
        #expect(context.isEffectivelyFullscreen)
    }

    @Test("Grounding context preserves window offsets for windowed captures")
    func groundingContextUsesWindowFrameWhenNotFullscreen() {
        let context = VisionScanner.groundingContext(
            screenshotWidth: 1280,
            screenshotHeight: 720,
            windowWidth: 900,
            windowHeight: 700,
            windowX: 100,
            windowY: 140,
            displayWidth: 1728,
            displayHeight: 1117
        )

        #expect(context.sidecarWidth == 900)
        #expect(context.sidecarHeight == 700)
        #expect(context.offsetX == 100)
        #expect(context.offsetY == 140)
        #expect(context.isEffectivelyFullscreen == false)

        let mappedPoint = context.mapToScreen(x: 25, y: 30)
        #expect(mappedPoint.x == 125)
        #expect(mappedPoint.y == 170)
    }

    @Test("Parse perception frame accepts a valid sidecar payload")
    func parsePerceptionFrameAcceptsValidPayload() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let response = VisionParseResponse(
            status: "success",
            elements: [
                VisionSidecarElement(
                    id: "button-1",
                    type: "button",
                    confidence: 0.9,
                    box: [50, 60, 120, 44],
                    text: "Continue",
                    source: "yolo"
                )
            ],
            count: 1,
            context: "Primary action in footer",
            error: nil
        )

        switch VisionScanner.parsePerceptionFrame(
            from: response,
            screenWidth: 1728,
            screenHeight: 1117,
            timestamp: timestamp
        ) {
        case .success(let frame):
            #expect(frame.detections.count == 1)
            #expect(frame.detections[0].id == "button-1")
            #expect(frame.detections[0].elementType == "button")
            #expect(frame.detections[0].frame.width == 120)
            #expect(frame.overallConfidence == 0.9)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test("Parse perception frame rejects invalid sidecar payloads")
    func parsePerceptionFrameRejectsInvalidPayload() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let response = VisionParseResponse(
            status: "partial",
            elements: [
                VisionSidecarElement(
                    id: "broken",
                    type: "button",
                    confidence: 0.75,
                    box: [10, 20, 30],
                    text: nil,
                    source: "parser"
                )
            ],
            count: 2,
            context: nil,
            error: "parser fallback required"
        )

        switch VisionScanner.parsePerceptionFrame(
            from: response,
            screenWidth: 1728,
            screenHeight: 1117,
            timestamp: timestamp
        ) {
        case .success:
            #expect(Bool(false))
        case .failure(let failure):
            #expect(
                failure.violations.contains(where: { $0.contains("parse error") })
            )
            #expect(
                failure.violations.contains(where: { $0.contains("count 2") })
            )
            #expect(
                failure.violations.contains(where: { $0.contains("invalid box payload") })
            )
            #expect(
                failure.violations.contains(where: { $0.contains("no detections") })
            )
        }
    }
}
