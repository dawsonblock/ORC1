import AppKit
import Foundation
import Observation
import OracleControllerShared

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case missionControl
    case control
    case recipes
    case traces
    case diagnostics
    case health
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .control: return "Control"
        case .recipes: return "Recipes"
        case .traces: return "Traces"
        case .diagnostics: return "Diagnostics"
        case .health: return "Health"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .missionControl: return "sparkle.magnifyingglass"
        case .control: return "switch.2"
        case .recipes: return "text.badge.checkmark"
        case .traces: return "waveform.path.ecg.rectangle"
        case .diagnostics: return "chart.xyaxis.line"
        case .health: return "cross.case"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum RecipeEditorMode: String, CaseIterable, Identifiable {
    case form
    case raw

    var id: String { rawValue }
}

struct ActionComposer {
    var kind: ActionKind = .focus
    var appName = ""
    var windowTitle = ""
    var query = ""
    var role = ""
    var domID = ""
    var text = ""
    var clearExisting = false
    var x = ""
    var y = ""
    var button = "left"
    var count = "1"
    var key = ""
    var modifiers = ""
    var direction = "down"
    var amount = "3"
    var waitCondition = "appFrontmost"
    var waitValue = ""
    var timeout = "10"
    var interval = "0.5"

    func makeRequest() -> ActionRequest {
        ActionRequest(
            kind: kind,
            appName: trimmedOrNil(appName),
            windowTitle: trimmedOrNil(windowTitle),
            query: trimmedOrNil(query),
            role: trimmedOrNil(role),
            domID: trimmedOrNil(domID),
            text: trimmedOrNil(text),
            clearExisting: clearExisting,
            x: doubleOrNil(x),
            y: doubleOrNil(y),
            button: trimmedOrNil(button),
            count: intOrNil(count),
            key: trimmedOrNil(key),
            modifiers: parsedModifiers,
            direction: trimmedOrNil(direction),
            amount: intOrNil(amount),
            waitCondition: trimmedOrNil(waitCondition),
            waitValue: trimmedOrNil(waitValue),
            timeout: doubleOrNil(timeout),
            interval: doubleOrNil(interval)
        )
    }

    mutating func hydrate(from snapshot: ControlSnapshot?) {
        guard let appName = snapshot?.observation.appName else { return }
        if self.appName.isEmpty {
            self.appName = appName
        }
    }

    private var parsedModifiers: [String]? {
        let values = modifiers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleOrNil(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func intOrNil(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@MainActor
@Observable
final class ControllerStore {
    var selectedSection: WorkspaceSection = .missionControl
    var session: ControllerSession?
    var snapshot: ControlSnapshot?
    var health: HealthStatus?
    var diagnostics: ControllerDiagnosticsSnapshot?
    var missionControl: MissionControlSnapshot?
    var productStatus: ProductEnvironmentStatus?
    var recipes: [RecipeDocument] = []
    var traceSessions: [TraceSessionSummary] = []
    var traceDetail: TraceSessionDetail?
    var approvalQueue: [ApprovalRequestDocument] = []
    var chatConversation: ChatConversation?
    var chatProviderStatus: ChatProviderStatus?
    var currentActionResult: ActionRunResult?
    var recentActions: [ActionRunResult] = []
    var latestRecipeRun: RecipeRunResultDocument?

    var selectedElementID: String?
    var selectedRecipeName: String?
    var selectedTraceSessionID: String?
    var selectedTraceStepID: String?
    var selectedGraphEdgeID: String?
    var selectedWorkflowID: String?
    var selectedExperimentID: String?
    var selectedProjectMemoryID: String?
    var selectedArchitectureFindingID: String?

    var actionComposer = ActionComposer()
    var recipeEditorMode: RecipeEditorMode = .form
    var draftRecipe = RecipeDocument(
        name: "new-recipe",
        description: "Operator workflow",
        steps: [RecipeStepDocument(id: 1, action: "focus")]
    )
    var rawRecipeText = ""
    var recipeRunParameters: [String: String] = [:]

    var monitorAppName = ""
    var autoRefreshEnabled = true
    var isBusy = false
    var isLoaded = false
    var showOnboarding = false
    var onboardingStep: OnboardingStep = .welcome
    var hostConnection: HostConnectionStatus = .idle

    var errorMessage: String?
    var inlineMessage: String?

    var recipeSearchText = ""
    var traceSearchText = ""
    var elementSearchText = ""
    var chatInput = ""

    var hostClient: HostProcessClient?
    let productEnvironmentManager = ProductEnvironmentManager()
    var diagnosticsRefreshTask: Task<Void, Never>?
    var missionControlRefreshTask: Task<Void, Never>?

    var filteredElements: [ElementSnapshot] {
        let elements = snapshot?.observation.elements ?? []
        let query = elementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return elements }
        return elements.filter {
            $0.label?.lowercased().contains(query) == true
                || $0.role?.lowercased().contains(query) == true
                || $0.value?.lowercased().contains(query) == true
        }
    }

    var filteredRecipes: [RecipeDocument] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
                || ($0.app?.lowercased().contains(query) ?? false)
        }
    }

    var filteredTraceSessions: [TraceSessionSummary] {
        let query = traceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return traceSessions }
        return traceSessions.filter { $0.id.lowercased().contains(query) }
    }

    var selectedElement: ElementSnapshot? {
        if let selectedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == selectedElementID })
        }

        if let focusedElementID = snapshot?.observation.focusedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == focusedElementID })
        }

        return snapshot?.observation.elements.first
    }

    var selectedTraceStep: TraceStepViewModel? {
        guard let selectedTraceStepID else { return traceDetail?.steps.first }
        return traceDetail?.steps.first(where: { $0.id == selectedTraceStepID })
    }

    var selectedGraphEdge: ControllerGraphEdgeDiagnostics? {
        let edges = (diagnostics?.graph.stableEdges ?? [])
            + (diagnostics?.graph.candidateEdges ?? [])
            + (diagnostics?.graph.recoveryEdges ?? [])
        guard let selectedGraphEdgeID else { return edges.first }
        return edges.first(where: { $0.id == selectedGraphEdgeID })
    }

    var selectedWorkflowDiagnostics: ControllerWorkflowDiagnostics? {
        guard let selectedWorkflowID else { return diagnostics?.workflows.first }
        return diagnostics?.workflows.first(where: { $0.id == selectedWorkflowID })
    }

    var selectedExperimentDiagnostics: ControllerExperimentDiagnostics? {
        guard let selectedExperimentID else { return diagnostics?.experiments.first }
        return diagnostics?.experiments.first(where: { $0.id == selectedExperimentID })
    }

    var selectedProjectMemoryDiagnostics: ControllerProjectMemoryDiagnostics? {
        guard let selectedProjectMemoryID else { return diagnostics?.projectMemory.first }
        return diagnostics?.projectMemory.first(where: { $0.id == selectedProjectMemoryID })
    }

    var selectedArchitectureFindingDiagnostics: ControllerArchitectureFindingDiagnostics? {
        guard let selectedArchitectureFindingID else { return diagnostics?.architectureFindings.first }
        return diagnostics?.architectureFindings.first(where: { $0.id == selectedArchitectureFindingID })
    }

    init() {
        self.hostClient = HostProcessClient(
            eventHandler: { [weak self] event in
                self?.handle(event)
            },
            lifecycleHandler: { [weak self] status in
                self?.apply(hostConnection: status)
            }
        )
    }

    func start() async {
        guard !isLoaded else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let environmentStatus = try productEnvironmentManager.prepareEnvironment()
            productStatus = environmentStatus
            showOnboarding = !productEnvironmentManager.isOnboardingCompleted()
            if environmentStatus.migrationStatus.didMigrateAnything {
                inlineMessage = [
                    environmentStatus.migrationStatus.seededSampleRecipes > 0 ? "Seeded \(environmentStatus.migrationStatus.seededSampleRecipes) sample recipes." : nil,
                    !environmentStatus.migrationStatus.migratedLegacyItems.isEmpty ? "Imported legacy data." : nil,
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            try await bootstrapHost()
            await loadDiagnostics()
            isLoaded = true
        } catch {
            present(error)
        }
    }

}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
