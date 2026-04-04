import Testing
@testable import OracleController
@testable import OracleControllerShared

@MainActor
struct ControllerStoreHostLifecycleTests {
    @Test
    func applyHostConnectionSurfacesLaunchFailure() {
        let store = ControllerStore()
        let failure = HostConnectionStatus.failed(reason: .binaryNotFound)

        store.apply(hostConnection: failure)

        #expect(store.hostConnection == failure)
        #expect(store.errorMessage == failure.detailText)
        #expect(store.isBusy == false)
    }

    @Test
    func applyHostConnectionClearsMatchingHostErrorOnReconnect() {
        let store = ControllerStore()
        let failure = HostConnectionStatus.disconnected(
            reason: .exited,
            detail: "OracleControllerHost exited with status 15."
        )

        store.apply(hostConnection: failure)
        store.apply(hostConnection: .connected)

        #expect(store.hostConnection == .connected)
        #expect(store.errorMessage == nil)
        #expect(store.inlineMessage == "OracleControllerHost reconnected.")
    }

    @Test
    func presentMapsHostClientErrorsToHostConnectionState() {
        let store = ControllerStore()
        let error = HostClientError.hostBinaryNotRunnable(path: "/tmp/OracleControllerHost")

        store.present(error)

        #expect(store.hostConnection.phase == .failed)
        #expect(store.hostConnection.failureReason == .binaryNotRunnable)
        #expect(store.errorMessage == error.errorDescription)
    }
}