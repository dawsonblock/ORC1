import Foundation
import Testing

@testable import OracleOS

@Suite("VisionBridge Lifecycle")
struct VisionBridgeLifecycleTests {
    final class StubBackgroundProcess: BackgroundProcess, @unchecked Sendable {
        let processIdentifier: Int32
        private(set) var terminateCallCount = 0

        init(processIdentifier: Int32) {
            self.processIdentifier = processIdentifier
        }

        func terminate() {
            terminateCallCount += 1
        }
    }

    private func health(
        status: String = "ready",
        modelPath: String = "/tmp/ShowUI-2B",
        modelExists: Bool = true,
        vlmLoadError: String? = nil
    ) -> VisionHealthResponse {
        VisionHealthResponse(
            status: status,
            version: "2.0.6",
            modelsLoaded: status == "ready" ? ["showui-2b"] : [],
            modelPath: modelPath,
            modelExists: modelExists,
            vlmLoadError: vlmLoadError,
            idleTimeout: 600,
            pid: 4242
        )
    }

    @Test("Failed sidecar start terminates spawned background process")
    func failedStartTerminatesSpawnedProcess() {
        let process = StubBackgroundProcess(processIdentifier: 4242)

        let result = VisionBridge.failSidecarStart(
            launchedProcess: process,
            message: "test failed launch"
        )

        #expect(result == false)
        #expect(process.terminateCallCount == 1)
    }

    @Test("Structured sidecar errors are flattened into a readable message")
    func extractsStructuredErrorPayload() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "error": "invalid request",
            "detail": "missing image",
            "suggestion": "capture a fresh screenshot",
        ])

        let message = VisionBridge.extractErrorMessage(from: data)

        #expect(
            message
                == "invalid request | missing image | Suggestion: capture a fresh screenshot"
        )
    }

    @Test("Health classification distinguishes ready, warming, and degraded sidecars")
    func classifiesHealthStates() {
        #expect(VisionBridge.assessSidecarAvailability(health(status: "ready")) == .ready)
        #expect(VisionBridge.assessSidecarAvailability(health(status: "idle")) == .warming)
        #expect(
            VisionBridge.assessSidecarAvailability(
                health(status: "idle", modelPath: "/missing/model", modelExists: false)
            ) == .degraded("Vision sidecar model path not found: /missing/model")
        )
        #expect(
            VisionBridge.assessSidecarAvailability(
                health(status: "idle", vlmLoadError: "mlx_vlm import failed")
            ) == .degraded("Vision sidecar model load failed: mlx_vlm import failed")
        )
    }

    @Test("Startup wait succeeds when sidecar becomes reachable while warming")
    func waitForSidecarSucceedsForWarmingHealth() {
        var attempts = 0

        let result = VisionBridge.waitForSidecar(
            maxAttempts: 3,
            sleep: { _ in attempts += 1 },
            availabilityProbe: {
                switch attempts {
                case 0:
                    return .unavailable(.timedOut)
                default:
                    return .warming
                }
            }
        )

        #expect(result)
        #expect(attempts == 1)
    }

    @Test("Startup wait fails immediately on degraded health")
    func waitForSidecarFailsImmediatelyForDegradedHealth() {
        var sleepCalls = 0

        let result = VisionBridge.waitForSidecar(
            maxAttempts: 5,
            sleep: { _ in sleepCalls += 1 },
            availabilityProbe: {
                .degraded("Vision sidecar model load failed: missing weights")
            }
        )

        #expect(result == false)
        #expect(sleepCalls == 0)
    }
}
