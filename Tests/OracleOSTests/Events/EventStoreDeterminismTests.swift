import XCTest
@testable import OracleOS

final class EventStoreDeterminismTests: XCTestCase {
    func testSameInputIdenticalSequence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try FileEventStore(root: tempDir)
        
        let commandID = UUID()
        let intentID = UUID()
        let event1 = EventEnvelope(
            sequenceNumber: 1,
            commandID: commandID,
            intentID: intentID,
            eventType: "test",
            payload: "{\"data\": 1}".data(using: .utf8)!
        )
        let event2 = EventEnvelope(
            sequenceNumber: 2,
            commandID: commandID,
            intentID: intentID,
            eventType: "test",
            payload: "{\"data\": 2}".data(using: .utf8)!
        )
        
        try await store.append(contentsOf: [event1, event2])
        
        let allEvents1 = try await store.all()
        
        // Re-open store to ensure properties are saved and loaded identically
        let store2 = try FileEventStore(root: tempDir)
        let allEvents2 = try await store2.all()
        
        XCTAssertEqual(allEvents1.count, 2)
        XCTAssertEqual(allEvents2.count, 2)
        
        for (e1, e2) in zip(allEvents1, allEvents2) {
            XCTAssertEqual(e1.sequenceNumber, e2.sequenceNumber)
            XCTAssertEqual(e1.commandID, e2.commandID)
            XCTAssertEqual(e1.intentID, e2.intentID)
            XCTAssertEqual(e1.eventType, e2.eventType)
            XCTAssertEqual(e1.payload, e2.payload)
        }
    }
}
