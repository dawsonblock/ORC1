import Foundation
import Testing
@testable import OracleOS

// MARK: - SkillResolutionError Tests

@Suite("SkillResolutionError")
struct SkillResolutionErrorTests {

    @Test("noCandidate maps to elementNotFound failure class")
    func noCandidateMapsToElementNotFound() {
        let error = SkillResolutionError.noCandidate("submit button")
        #expect(error.failureClass == .elementNotFound)
    }

    @Test("ambiguousTarget maps to elementAmbiguous failure class")
    func ambiguousTargetMapsToElementAmbiguous() {
        let error = SkillResolutionError.ambiguousTarget("button", 0.15)
        #expect(error.failureClass == .elementAmbiguous)
    }

    @Test("noCandidate errors are equal when labels match; not equal when labels differ")
    func noCandidateEquality() {
        let a = SkillResolutionError.noCandidate("x")
        let b = SkillResolutionError.noCandidate("x")
        let c = SkillResolutionError.noCandidate("y")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("ambiguousTarget errors compare by label and score")
    func ambiguousTargetEquality() {
        let a = SkillResolutionError.ambiguousTarget("btn", 0.1)
        let b = SkillResolutionError.ambiguousTarget("btn", 0.1)
        let c = SkillResolutionError.ambiguousTarget("btn", 0.2)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - SkillResolution Tests

@Suite("SkillResolution")
struct SkillResolutionTests {

    @Test("Init stores intent and optional fields")
    func initStoresFields() {
        let intent = ActionIntent(
            agentKind: .os,
            app: "Safari",
            name: "click",
            action: "click"
        )
        let query = ElementQuery(text: "Submit", role: "button")
        let resolution = SkillResolution(intent: intent, selectedCandidate: nil, semanticQuery: query)
        #expect(resolution.intent == intent)
        #expect(resolution.selectedCandidate == nil)
        #expect(resolution.semanticQuery?.text == "Submit")
        #expect(resolution.repositorySnapshotID == nil)
    }
}

// MARK: - SkillRegistry Tests

@Suite("SkillRegistry")
struct SkillRegistryTests {

    @Test("Register and retrieve a Skill by name")
    func registerAndRetrieveSkill() {
        let registry = SkillRegistry()
        let skill = OpenAppSkill()
        registry.register(skill)
        let retrieved = registry.get("open_app")
        #expect(retrieved != nil)
        #expect(retrieved?.name == "open_app")
    }

    @Test("Returns nil for unregistered skill name")
    func returnsNilForMissingSkill() {
        let registry = SkillRegistry()
        #expect(registry.get("nonexistent") == nil)
    }

    @Test("Registering a skill with the same name replaces previous registration")
    func registrationReplacesDuplicate() {
        let registry = SkillRegistry()
        registry.register(OpenAppSkill())
        registry.register(OpenAppSkill())
        // No crash; only one entry with that name
        #expect(registry.get("open_app") != nil)
    }

    // MARK: - live() factory

    @Test("live() registry contains click skill")
    func liveContainsClick() {
        let registry = SkillRegistry.live()
        #expect(registry.get("click") != nil)
    }

    @Test("live() registry contains type skill")
    func liveContainsType() {
        let registry = SkillRegistry.live()
        #expect(registry.get("type") != nil)
    }

    @Test("live() registry contains scroll skill")
    func liveContainsScroll() {
        let registry = SkillRegistry.live()
        #expect(registry.get("scroll") != nil)
    }

    @Test("live() registry contains open_app skill")
    func liveContainsOpenApp() {
        let registry = SkillRegistry.live()
        #expect(registry.get("open_app") != nil)
    }

    @Test("live() registry contains switch_window skill")
    func liveContainsSwitchWindow() {
        let registry = SkillRegistry.live()
        #expect(registry.get("switch_window") != nil)
    }

    @Test("live() registry contains fill_form skill")
    func liveContainsFillForm() {
        let registry = SkillRegistry.live()
        #expect(registry.get("fill_form") != nil)
    }

    @Test("live() registry contains read_file skill")
    func liveContainsReadFile() {
        let registry = SkillRegistry.live()
        #expect(registry.get("read_file") != nil)
    }
}

// MARK: - Simple Skill Behaviour Tests

@Suite("OpenAppSkill")
struct OpenAppSkillTests {

    @Test("Resolve uses query.app when available")
    func resolvePrefersQueryApp() throws {
        let skill = OpenAppSkill()
        let query = ElementQuery(app: "Finder")
        let state = WorldState(observation: Observation(app: "Safari", windowTitle: "Test"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.app == "Finder")
    }

    @Test("Resolve falls back to query.text when app is nil")
    func resolveFallsBackToText() throws {
        let skill = OpenAppSkill()
        let query = ElementQuery(text: "TextEdit", app: nil)
        let state = WorldState(observation: Observation(app: "Safari", windowTitle: "Test"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.app == "TextEdit")
    }

    @Test("Resolve defaults to Finder when both app and text are nil")
    func resolveDefaultsFinder() throws {
        let skill = OpenAppSkill()
        let query = ElementQuery()
        let state = WorldState(observation: Observation(app: "Safari", windowTitle: "Test"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.app == "Finder")
    }

    @Test("Name is open_app")
    func skillName() {
        #expect(OpenAppSkill().name == "open_app")
    }
}

@Suite("ScrollSkill")
struct ScrollSkillTests {

    @Test("Name is scroll")
    func skillName() {
        #expect(ScrollSkill().name == "scroll")
    }

    @Test("Resolve produces scroll action intent")
    func resolveProducesScrollIntent() throws {
        let skill = ScrollSkill()
        let query = ElementQuery(text: "down", app: "Safari")
        let state = WorldState(observation: Observation(app: "Safari", windowTitle: "Test"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.action == "scroll")
    }

    @Test("Resolve uses state observation app when query.app is nil")
    func resolveUsesStateApp() throws {
        let skill = ScrollSkill()
        let query = ElementQuery(text: "up", app: nil)
        let state = WorldState(observation: Observation(app: "Mail", windowTitle: "Inbox"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.app == "Mail")
    }
}

@Suite("SwitchWindowSkill")
struct SwitchWindowSkillTests {

    @Test("Name is switch_window")
    func skillName() {
        #expect(SwitchWindowSkill().name == "switch_window")
    }

    @Test("Resolve uses query.app when provided")
    func resolveUsesQueryApp() throws {
        let skill = SwitchWindowSkill()
        let query = ElementQuery(text: "Document", app: "Pages")
        let state = WorldState(observation: Observation(app: "Safari", windowTitle: "Test"))
        let memoryStore = UnifiedMemoryStore(appMemory: StrategyMemory())
        let resolution = try skill.resolve(query: query, state: state, memoryStore: memoryStore)
        #expect(resolution.intent.app == "Pages")
    }
}
