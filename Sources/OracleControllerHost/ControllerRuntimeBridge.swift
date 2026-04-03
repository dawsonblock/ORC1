import AppKit
import ApplicationServices
import Foundation
import OracleControllerShared
import OracleOS

@MainActor
final class ControllerRuntimeBridge {
    let sessionID: String
    let sessionStartedAt: Date
    let oracleRuntime: RuntimeOrchestrator
    let runtimeLifecycle: RuntimeLifecycle
    let diagnosticsBuilder: RuntimeDiagnosticsBuilder
    
    /// The bootstrapped runtime bundle — single authority for all services.
    private let bootstrappedRuntime: BootstrappedRuntime
    
    /// Direct container access — the single runtime authority.
    var container: RuntimeContainer { bootstrappedRuntime.container }

    /// Convenience accessors for tracing services (from unified container)
    var traceRecorder: TraceRecorder { bootstrappedRuntime.container.traceRecorder }
    var traceStore: ExperienceStore { bootstrappedRuntime.container.traceStore }
    var artifactWriter: FailureArtifactWriter { bootstrappedRuntime.container.artifactWriter }

    init() async throws {
        // Single source of truth: RuntimeBootstrap creates all shared services with recovery
        let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .live())
        self.bootstrappedRuntime = bootstrapped
        
        // Log recovery status
        if bootstrapped.recoveryReport.didRecover {
            Log.info("Controller runtime recovered: replayed \(bootstrapped.recoveryReport.eventsReplayed) events")
        }
        
        // Pull context from the unified container
        self.oracleRuntime = bootstrapped.orchestrator
        self.diagnosticsBuilder = RuntimeDiagnosticsBuilder()
        
        self.runtimeLifecycle = RuntimeLifecycle(approvalStore: bootstrapped.container.approvalStore)
        self.sessionID = bootstrapped.container.traceRecorder.sessionID
        self.sessionStartedAt = Date()
        self.runtimeLifecycle.startControllerHeartbeat(sessionID: sessionID)
    }

    func currentSession(autoRefreshEnabled: Bool, appName: String?) -> ControllerSession {
        ControllerSession(
            id: sessionID,
            startedAt: sessionStartedAt,
            hostProcessID: getpid(),
            activeAppName: appName ?? NSWorkspace.shared.frontmostApplication?.localizedName,
            autoRefreshEnabled: autoRefreshEnabled
        )
    }

    func refreshSnapshot(appName: String?) -> ControlSnapshot {
        let observation = ObservationBuilder.capture(appName: appName)
        let screenshot = screenshotFrame(appName: appName)
        return ControlSnapshot(observation: map(observation), screenshot: screenshot)
    }

    func healthStatus() -> HealthStatus {
        let claudeConfig = loadClaudeConfig()
        let claudeConfigured = (claudeConfig?["mcpServers"] as? [String: Any])?["oracle-os"] != nil
        let health = VisionBridge.healthCheck()
        let permissions = [
            PermissionStatus(
                id: "accessibility",
                title: "Accessibility",
                granted: AXIsProcessTrusted(),
                detail: AXIsProcessTrusted() ? "Runtime can inspect and act on apps." : "Grant in System Settings > Privacy & Security > Accessibility."
            ),
            PermissionStatus(
                id: "screen-recording",
                title: "Screen Recording",
                granted: ScreenCapture.hasPermission(),
                detail: ScreenCapture.hasPermission() ? "Live monitor screenshots are available." : "Grant in System Settings > Privacy & Security > Screen Recording."
            ),
        ]

        return HealthStatus(
            runtimeVersion: OracleOS.version,
            permissions: permissions,
            claudeConfigured: claudeConfigured,
            visionSidecarRunning: VisionBridge.isAvailable(),
            visionSidecarVersion: health?["version"] as? String,
            visionModelPath: VisionBridge.findModelPath(),
            recipeDirectoryPath: OracleProductPaths.recipesDirectory.path,
            recipeCount: RecipeStore.listRecipes().count,
            traceDirectoryPath: ExperienceStore.traceRootDirectory().path,
            applicationSupportPath: OracleProductPaths.dataRootDirectory.path,
            approvalsDirectoryPath: OracleProductPaths.approvalsDirectory.path,
            projectMemoryDirectoryPath: OracleProductPaths.projectMemoryDirectory.path,
            experimentsDirectoryPath: OracleProductPaths.experimentsDirectory.path,
            logsDirectoryPath: OracleProductPaths.logsDirectory.path,
            graphDatabasePath: OracleProductPaths.graphDatabaseURL.path,
            approvalBrokerActive: container.approvalStore.isActive(),
            controllerConnected: runtimeLifecycle.controllerConnected(),
            policyMode: container.config.policyMode.rawValue,
            runningFromAppBundle: OracleProductPaths.runningFromAppBundle,
            bundledHostAvailable: OracleProductPaths.runningFromAppBundle,
            bundledVisionBootstrapAvailable: OracleProductPaths.bundledVisionBootstrapDirectory != nil,
            visionInstallPath: OracleProductPaths.visionInstallDirectory.path,
            buildVersion: OracleProductPaths.buildVersion,
            buildNumber: OracleProductPaths.buildNumber
        )
    }

    func diagnosticsSnapshot() -> ControllerDiagnosticsSnapshot {
        let traceEvents = diagnosticsBuilder.loadTraceEvents()
        let observation = ObservationBuilder.capture(appName: nil)
        let hostSnapshot = container.automationHost.snapshots.captureSnapshot(appName: observation.app)
        let browserSession = container.browserController.snapshot(
            appName: observation.app,
            observation: observation
        ).map { BrowserSession(appName: observation.app ?? $0.browserApp, page: $0, available: true) }
        let snapshot = diagnosticsBuilder.build(
            graphStore: container.graphStore,
            traceEvents: traceEvents,
            hostSnapshot: hostSnapshot,
            browserSession: browserSession
        )
        return map(snapshot)
    }

    func executeAction(_ request: ActionRequest) -> ActionRunResult {
        let result: ToolResult = switch request.kind {
        case .focus:
            Actions.focusApp(
                appName: request.appName ?? "",
                windowTitle: request.windowTitle,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_focus"
            )

        case .click:
            Actions.click(
                query: request.query,
                role: request.role,
                domId: request.domID,
                appName: request.appName,
                x: request.x,
                y: request.y,
                button: request.button,
                count: request.count,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_click"
            )

        case .type:
            Actions.typeText(
                text: request.text ?? "",
                into: request.query,
                domId: request.domID,
                appName: request.appName,
                clear: request.clearExisting,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_type"
            )

        case .press:
            Actions.pressKey(
                key: request.key ?? "",
                modifiers: request.modifiers,
                appName: request.appName,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_press"
            )

        case .scroll:
            Actions.scroll(
                direction: request.direction ?? "down",
                amount: request.amount,
                appName: request.appName,
                x: request.x,
                y: request.y,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_scroll"
            )

        case .wait:
            WaitManager.waitFor(
                condition: request.waitCondition ?? "appFrontmost",
                value: request.waitValue,
                appName: request.appName,
                timeout: request.timeout ?? 10,
                interval: request.interval ?? 0.5
            )
        }

        return mapActionResult(request: request, result: result)
    }

    func listRecipes() -> [RecipeDocument] {
        RecipeStore.listRecipes().map(map)
    }

    func loadRecipe(named name: String) -> RecipeDocument? {
        RecipeStore.loadRecipe(named: name).map(map)
    }

    func saveRecipe(_ document: RecipeDocument) throws -> RecipeDocument {
        let savedName: String
        if let rawJSON = document.rawJSON, !rawJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savedName = try RecipeStore.saveRecipeJSON(rawJSON)
        } else {
            try RecipeStore.saveRecipe(try map(document))
            savedName = document.name
        }
        guard let saved = loadRecipe(named: savedName) else {
            throw OracleError.actionFailed(description: "Saved recipe could not be reloaded")
        }
        return saved
    }

    func deleteRecipe(named name: String) -> Bool {
        RecipeStore.deleteRecipe(named: name)
    }

    func runRecipe(named name: String, params: [String: String]) -> RecipeRunResultDocument {
        guard let recipe = RecipeStore.loadRecipe(named: name) else {
            return RecipeRunResultDocument(
                recipeName: name,
                success: false,
                stepsCompleted: 0,
                totalSteps: 0,
                error: "Recipe not found",
                traceSessionID: sessionID,
                stepResults: []
            )
        }

        let result = RecipeEngine.run(
            recipe: recipe,
            params: params,
            runtime: oracleRuntime,
            taskID: sessionID
        )
        return mapRecipeRunResult(recipeName: name, totalStepsFallback: recipe.steps.count, result: result)
    }

    func resumeRecipe(resumeToken: String, approvalRequestID: String?) -> RecipeRunResultDocument {
        let result = RecipeEngine.resume(
            resumeToken: resumeToken,
            approvalRequestID: approvalRequestID,
            runtime: oracleRuntime,
            taskID: sessionID
        )
        let recipeName = (result.data?["recipe"] as? String) ?? "recipe"
        let recipe = RecipeStore.loadRecipe(named: recipeName)
        return mapRecipeRunResult(
            recipeName: recipeName,
            totalStepsFallback: recipe?.steps.count ?? 0,
            result: result
        )
    }

    func listApprovalRequests() -> [ApprovalRequestDocument] {
        container.approvalStore.listPendingRequests().map(map)
    }

    func approveApprovalRequest(id: String) throws -> ApprovalReceipt {
        try container.approvalStore.approve(requestID: id)
    }

    func rejectApprovalRequest(id: String) throws {
        try container.approvalStore.reject(requestID: id)
    }

    func recordedSteps(since count: Int) -> [TraceStepViewModel] {
        Array(traceRecorder.allEvents().dropFirst(count)).map(map)
    }

    func recordedStepCount() -> Int {
        traceRecorder.allEvents().count
    }

    func listTraceSessions() -> [TraceSessionSummary] {
        let directory = ExperienceStore.resolveSessionsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { fileURL in
                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                let lineCount = (try? String(contentsOf: fileURL, encoding: .utf8).split(separator: "\n").count) ?? 0
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                return TraceSessionSummary(id: sessionID, stepCount: lineCount, lastUpdated: values?.contentModificationDate)
            }
            .sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
    }

    func loadTraceSession(id: String) -> TraceSessionDetail? {
        let fileURL = ExperienceStore.resolveSessionsDirectory().appendingPathComponent("\(id).jsonl")
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let decoder = ControllerJSONCoding.makeDecoder()

        let steps = contents
            .split(separator: "\n")
            .compactMap { line -> TraceEvent? in
                try? decoder.decode(TraceEvent.self, from: Data(line.utf8))
            }
            .map(map)

        let summary = TraceSessionSummary(
            id: id,
            stepCount: steps.count,
            lastUpdated: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        )

        return TraceSessionDetail(summary: summary, steps: steps)
    }

}
