import Foundation
import Testing
@testable import OracleOS

/// Tests that prove StateSnapshot immutability contract.
struct StateSnapshotTests {

    @Test func snapshotHoldsValueNotReference() {
        // Create a WorldModelSnapshot (value type)
        let worldSnapshot = WorldModelSnapshot(
            timestamp: Date(),
            cycleCount: 10,
            activeApplication: "Xcode",
            windowTitle: "Project.swift",
            visibleElementCount: 42,
            notes: ["test=1"]
        )

        // Create a StateSnapshot holding that value
        let stateSnapshot = StateSnapshot(
            sequenceNumber: 5,
            state: worldSnapshot,
            eventAncestry: [UUID(), UUID()]
        )

        // Verify all fields are preserved
        #expect(stateSnapshot.state.cycleCount == 10)
        #expect(stateSnapshot.state.activeApplication == "Xcode")
        #expect(stateSnapshot.state.windowTitle == "Project.swift")
        #expect(stateSnapshot.state.visibleElementCount == 42)
        #expect(stateSnapshot.state.notes.contains("test=1"))
        #expect(stateSnapshot.sequenceNumber == 5)
        #expect(stateSnapshot.eventAncestry.count == 2)
    }

    @Test func snapshotIsCodable() throws {
        let worldSnapshot = WorldModelSnapshot(
            timestamp: Date(),
            cycleCount: 7,
            activeApplication: "Terminal",
            visibleElementCount: 3
        )

        let original = StateSnapshot(
            sequenceNumber: 99,
            state: worldSnapshot,
            eventAncestry: [UUID()]
        )

        // Encode and decode
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(StateSnapshot.self, from: data)

        #expect(decoded.sequenceNumber == original.sequenceNumber)
        #expect(decoded.state.cycleCount == original.state.cycleCount)
        #expect(decoded.state.activeApplication == original.state.activeApplication)
        #expect(decoded.eventAncestry.count == original.eventAncestry.count)
    }

    @Test func mutatingLiveModelDoesNotChangeSnapshot() {
        // Create a live model
        let liveModel = WorldStateModel()

        // Take a snapshot of its current state
        let capturedSnapshot = liveModel.snapshot

        // Create a StateSnapshot from it
        let stateSnapshot = StateSnapshot(
            sequenceNumber: 1,
            state: capturedSnapshot,
            eventAncestry: []
        )

        // Now mutate the live model
        liveModel.update { snapshot in
            snapshot.copy(cycleCount: 999, notes: ["mutated"])
        }

        // The StateSnapshot must NOT reflect the mutation
        #expect(stateSnapshot.state.cycleCount == 0, "Snapshot must not change after live model mutation")
        #expect(stateSnapshot.state.notes.contains("mutated") == false)

        // But the live model DID change
        #expect(liveModel.snapshot.cycleCount == 999)
        #expect(liveModel.snapshot.notes.contains("mutated"))
    }
}
