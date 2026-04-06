import Foundation
import OracleControllerShared
import OracleOS

private struct RuntimeControlSettingsDocument: Codable {
    let selectedPreset: RuntimeControlPreset
    let updatedAt: Date
}

struct RuntimeControlSettingsStore {
    let fileURL: URL

    init(fileURL: URL = OracleProductPaths.runtimeControlSettingsURL) {
        self.fileURL = fileURL
    }

    func loadSelectedPreset() -> RuntimeControlPreset? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            let document = try ControllerJSONCoding.makeDecoder().decode(RuntimeControlSettingsDocument.self, from: data)
            return document.selectedPreset
        } catch {
            Log.warn("Runtime control settings could not be decoded: \(error.localizedDescription)")
            return nil
        }
    }

    func saveSelectedPreset(_ preset: RuntimeControlPreset) throws {
        try OracleProductPaths.ensureUserDirectories()
        let document = RuntimeControlSettingsDocument(selectedPreset: preset, updatedAt: Date())
        let encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }
}

extension RuntimeControlPreset {
    var policyMode: PolicyMode {
        switch self {
        case .fullControl:
            return .open
        case .original:
            return .confirmRisky
        case .less:
            return .lockedDown
        case .aiDecides:
            return .adaptive
        }
    }

    init(policyMode: PolicyMode) {
        switch policyMode {
        case .open:
            self = .fullControl
        case .confirmRisky:
            self = .original
        case .lockedDown:
            self = .less
        case .adaptive:
            self = .aiDecides
        }
    }
}