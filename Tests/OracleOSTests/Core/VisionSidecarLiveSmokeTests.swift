import Foundation
import XCTest

@testable import OracleOS

final class VisionSidecarLiveSmokeTests: XCTestCase {
    private func requireLiveSmokeEnabled() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ORACLE_LIVE_VISION_SMOKE"] == "1",
            "Set ORACLE_LIVE_VISION_SMOKE=1 to run the optional live vision sidecar smoke test."
        )
    }

    private func baseURLString() -> String {
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["ORACLE_VISION_URL"]
            ?? "http://127.0.0.1:\(environment["ORACLE_VISION_PORT"] ?? "9876")"
        return configured.hasSuffix("/") ? String(configured.dropLast()) : configured
    }

    private func endpointURL(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: baseURLString() + path))
    }

    func testLiveHealthAndGroundFailurePath() async throws {
        try requireLiveSmokeEnabled()

        let healthURL = try endpointURL(VisionSidecarEndpoint.health)
        let (healthData, healthResponse) = try await URLSession.shared.data(from: healthURL)
        let healthHTTP = try XCTUnwrap(healthResponse as? HTTPURLResponse)
        XCTAssertEqual(healthHTTP.statusCode, 200)

        let health = try JSONDecoder().decode(VisionHealthResponse.self, from: healthData)
        XCTAssertTrue(["ready", "idle"].contains(health.status))

        let status = VisionBridge.sidecarStatus()
        XCTAssertNotEqual(status.state, .unavailable)

        var request = URLRequest(url: try endpointURL(VisionSidecarEndpoint.ground))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "description": "intentional live smoke validation failure",
            "screen_w": 1728,
            "screen_h": 1117,
        ])

        let (failureData, failureResponse) = try await URLSession.shared.data(for: request)
        let failureHTTP = try XCTUnwrap(failureResponse as? HTTPURLResponse)
        XCTAssertGreaterThanOrEqual(failureHTTP.statusCode, 400)
        XCTAssertLessThan(failureHTTP.statusCode, 600)
        XCTAssertNotNil(VisionBridge.extractErrorMessage(from: failureData))
    }
}