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
}
