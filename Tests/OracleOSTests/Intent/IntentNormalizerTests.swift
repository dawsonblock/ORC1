import Foundation
import Testing
@testable import OracleOS

@Suite("IntentNormalizer")
struct IntentNormalizerTests {

    private let normalizer = IntentNormalizer()

    // MARK: - Explicit domain

    @Test("Explicit domain is preserved")
    func explicitDomainPreserved() {
        let intent = normalizer.normalize(raw: "do something", domain: .code)
        #expect(intent.domain == .code)
    }

    @Test("Explicit system domain is preserved regardless of text")
    func explicitSystemDomainPreserved() {
        let intent = normalizer.normalize(raw: "click the button", domain: .system)
        #expect(intent.domain == .system)
    }

    // MARK: - Domain inference: UI

    @Test("Infers UI domain for 'click' keyword")
    func infersUIDomainForClick() {
        let intent = normalizer.normalize(raw: "click the submit button")
        #expect(intent.domain == .ui)
    }

    @Test("Infers UI domain for 'type' keyword")
    func infersUIDomainForType() {
        let intent = normalizer.normalize(raw: "type my password into the field")
        #expect(intent.domain == .ui)
    }

    @Test("Infers UI domain for 'focus' keyword")
    func infersUIDomainForFocus() {
        let intent = normalizer.normalize(raw: "focus on the search box")
        #expect(intent.domain == .ui)
    }

    // MARK: - Domain inference: Code

    @Test("Infers code domain for 'build' keyword")
    func infersCodeDomainForBuild() {
        let intent = normalizer.normalize(raw: "build the project")
        #expect(intent.domain == .code)
    }

    @Test("Infers code domain for 'test' keyword")
    func infersCodeDomainForTest() {
        let intent = normalizer.normalize(raw: "run tests and check coverage")
        #expect(intent.domain == .code)
    }

    @Test("Infers code domain for 'file' keyword")
    func infersCodeDomainForFile() {
        let intent = normalizer.normalize(raw: "read the config file")
        #expect(intent.domain == .code)
    }

    // MARK: - Domain inference: System

    @Test("Infers system domain for 'open' keyword")
    func infersSystemDomainForOpen() {
        let intent = normalizer.normalize(raw: "open Safari")
        #expect(intent.domain == .system)
    }

    @Test("Infers system domain for 'launch' keyword")
    func infersSystemDomainForLaunch() {
        let intent = normalizer.normalize(raw: "launch the application")
        #expect(intent.domain == .system)
    }

    // MARK: - Domain inference: Mixed (fallback)

    @Test("Falls back to mixed domain for unrecognized text")
    func fallsBackToMixed() {
        let intent = normalizer.normalize(raw: "do something unrecognized")
        #expect(intent.domain == .mixed)
    }

    // MARK: - Objective

    @Test("Objective is trimmed raw input")
    func objectiveTrimmed() {
        let intent = normalizer.normalize(raw: "  click the button  ")
        #expect(intent.objective == "click the button")
    }

    @Test("Default priority is normal")
    func defaultPriorityIsNormal() {
        let intent = normalizer.normalize(raw: "build project")
        #expect(intent.priority == .normal)
    }
}
