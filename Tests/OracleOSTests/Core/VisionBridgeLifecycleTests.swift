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
}
