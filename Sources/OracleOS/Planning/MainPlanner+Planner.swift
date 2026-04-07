import Foundation

// MARK: - MainPlanner + Planner conformance
// Makes MainPlanner available as the `Planner` implementation in RuntimeOrchestrator.

extension MainPlanner: Planner {
    /// Route-only façade: dispatch to the appropriate domain planner based on intent domain.
    /// INVARIANT: planners return Commands only — no execution, no state writes.
    public func plan(intent: Intent, context: PlannerContext) async throws -> Command {
        switch intent.domain {
        case .ui:
            return try await planUIIntent(intent, context: context)
        case .code:
            return try await planCodeIntent(intent, context: context)
        case .system, .mixed:
            return try await planSystemIntent(intent, context: context)
        }
    }

    private func resolvedWorkspacePath(intent: Intent, context: PlannerContext) -> String? {
        func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        return normalized(intent.metadata["workspacePath"])
            ?? normalized(intent.metadata["workspaceRoot"])
            ?? normalized(context.repositorySnapshot?.workspaceRoot)
    }

    private func preferredModuleHint(from memories: [MemoryCandidate]) -> String? {
        func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }

        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: ",:;()[]{}")
        )

        for memory in memories {
            let tokens = memory.content.components(separatedBy: separators)
            if let pathLikeToken = tokens.first(where: {
                $0.contains("/")
                    || $0.hasSuffix(".swift")
                    || $0.hasSuffix(".md")
                    || $0.hasSuffix(".bc")
                    || $0.hasSuffix(".json")
            }), let hint = normalized(pathLikeToken) {
                return hint
            }
        }

        for memory in memories {
            let basename = URL(fileURLWithPath: memory.source)
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            if let hint = normalized(basename) {
                return hint
            }
        }

        for memory in memories {
            let prefix = memory.content
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init)
            if let hint = normalized(prefix) {
                return hint
            }
        }

        return nil
    }

    private func memoryNotes(from memories: [MemoryCandidate]) -> [String] {
        guard !memories.isEmpty else {
            return []
        }

        func sanitized(_ value: String) -> String {
            value.lowercased()
                .replacingOccurrences(
                    of: "[^a-z0-9._/-]+",
                    with: "-",
                    options: .regularExpression
                )
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        var notes = ["memory-count=\(memories.count)"]
        if let hint = preferredModuleHint(from: memories) {
            let token = sanitized(hint)
            if !token.isEmpty {
                notes.append("memory-hint=\(token)")
            }
        }
        for source in memories.prefix(2).map(\.source) {
            let token = sanitized(URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent)
            if !token.isEmpty {
                let note = "memory-source=\(token)"
                if !notes.contains(note) {
                    notes.append(note)
                }
            }
        }
        return notes
    }

    // MARK: - Domain Planners

    private func planUIIntent(_ intent: Intent, context: PlannerContext) async throws -> Command {
        if let actionIntent = decodeActionIntent(from: intent) {
            return commandFrom(actionIntent: actionIntent, fallbackIntent: intent)
        }

        // Route UI intents to click/type/focus/read based on objective
        let objective = intent.objective.lowercased()
        let metadata = CommandMetadata(intentID: intent.id, source: "planner.ui")

        if objective.contains("click") || objective.contains("tap") || objective.contains("press") {
            let targetID = intent.metadata["targetID"] ?? intent.metadata["query"] ?? intent.objective
            let app = intent.metadata["app"] ?? context.state.snapshot.activeApplication ?? "unknown"
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "click", app: app, query: targetID)),
                metadata: metadata
            )
        }

        if objective.contains("type") || objective.contains("enter") || objective.contains("input") {
            let text = intent.metadata["text"] ?? intent.objective
            let targetID = intent.metadata["targetID"] ?? intent.metadata["query"] ?? "focused"
            let app = intent.metadata["app"] ?? context.state.snapshot.activeApplication
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "type", app: app, query: targetID, text: text)),
                metadata: metadata
            )
        }

        if objective.contains("focus") || objective.contains("switch") || objective.contains("activate") {
            let app = intent.metadata["app"] ?? context.state.snapshot.activeApplication ?? "unknown"
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "focus", app: app)),
                metadata: metadata
            )
        }

        if objective.contains("read") || objective.contains("get") || objective.contains("observe") {
            let targetID = intent.metadata["targetID"] ?? intent.metadata["query"] ?? intent.objective
            let app = intent.metadata["app"] ?? context.state.snapshot.activeApplication
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "read", app: app, query: targetID)),
                metadata: metadata
            )
        }

        // Default: try to focus the active app
        let app = context.state.snapshot.activeApplication ?? "unknown"
        return Command(type: .ui, payload: .ui(UIAction(name: "focus", app: app)), metadata: metadata)
    }

    private func planCodeIntent(_ intent: Intent, context: PlannerContext) async throws -> Command {
        if let actionIntent = decodeActionIntent(from: intent) {
            return commandFrom(actionIntent: actionIntent, fallbackIntent: intent)
        }

        let objective = intent.objective.lowercased()
        let workspacePath = resolvedWorkspacePath(intent: intent, context: context)
        let moduleHint = preferredModuleHint(from: context.memories)
        let memoryTraceTags = memoryNotes(from: context.memories)
        let baseQuery = intent.metadata["query"] ?? intent.objective
        let searchQuery = moduleHint.map { "\($0) \(baseQuery)" } ?? baseQuery
        let hintedPath = moduleHint.flatMap { hint -> String? in
            let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.contains("/") || trimmed.contains(".") else {
                return nil
            }
            return trimmed
        }

        if objective.contains("search") || objective.contains("find") || objective.contains("query") {
            return Command(
                type: CommandType.code,
                payload: .code(CodeAction(name: "searchRepository", query: searchQuery, workspacePath: workspacePath)),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "planner.code",
                    traceTags: memoryTraceTags + (moduleHint == nil ? [] : ["memory-hint-applied"])
                )
            )
        }

        if objective.contains("read") || objective.contains("open") || objective.contains("view") {
            let path = intent.metadata["filePath"] ?? hintedPath ?? intent.objective
            return Command(
                type: CommandType.code,
                payload: .code(CodeAction(name: "readFile", filePath: path, workspacePath: workspacePath)),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "planner.code",
                    traceTags: memoryTraceTags + (hintedPath == nil || intent.metadata["filePath"] != nil ? [] : ["memory-hint-applied"])
                )
            )
        }

        if objective.contains("edit") || objective.contains("modify") || objective.contains("patch") {
            let path = intent.metadata["filePath"] ?? ""
            let patch = intent.metadata["patch"] ?? intent.objective
            guard let workspacePath else {
                // Cannot construct a FileMutationSpec without a workspace root.
                // Fall back to a read-only code command so the pipeline fails cleanly.
                return Command(
                    type: CommandType.code,
                    payload: .code(CodeAction(name: "readFile", filePath: path)),
                    metadata: CommandMetadata(
                        intentID: intent.id,
                        source: "planner.code",
                        traceTags: memoryTraceTags + ["fail-closed", "missing-workspace-root", "edit-demoted-to-read"]
                    )
                )
            }
            return Command(
                type: CommandType.code,
                payload: .file(FileMutationSpec(path: path, operation: .write, content: patch, workspaceRoot: workspacePath)),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "planner.code",
                    traceTags: memoryTraceTags
                )
            )
        }

        if objective.contains("build") || objective.contains("compile") {
            let workspacePath = workspacePath ?? FileManager.default.currentDirectoryPath
            let spec = BuildSpec(
                workspaceRoot: workspacePath,
                configuration: intent.metadata["configuration"] ?? "Debug"
            )
            return Command(
                type: CommandType.code,
                payload: .build(spec),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "planner.code",
                    traceTags: memoryTraceTags
                )
            )
        }

        if objective.contains("test") || objective.contains("run test") {
            let workspacePath = workspacePath ?? FileManager.default.currentDirectoryPath
            let spec = TestSpec(
                workspaceRoot: workspacePath,
                filter: intent.metadata["filter"]
            )
            return Command(
                type: CommandType.code,
                payload: .test(spec),
                metadata: CommandMetadata(
                    intentID: intent.id,
                    source: "planner.code",
                    traceTags: memoryTraceTags
                )
            )
        }

        return Command(
            type: CommandType.code,
            payload: .code(CodeAction(name: "searchRepository", query: searchQuery, workspacePath: workspacePath)),
            metadata: CommandMetadata(
                intentID: intent.id,
                source: "planner.code",
                traceTags: memoryTraceTags + (moduleHint == nil ? [] : ["memory-hint-applied"])
            )
        )
    }

    private func planSystemIntent(_ intent: Intent, context: PlannerContext) async throws -> Command {
        if let actionIntent = decodeActionIntent(from: intent) {
            return commandFrom(actionIntent: actionIntent, fallbackIntent: intent)
        }

        let objective = intent.objective.lowercased()
        let metadata = CommandMetadata(intentID: intent.id, source: "planner.system")

        if objective.contains("launch") || objective.contains("open app") || objective.contains("start") {
            let bundleID = intent.metadata["bundleID"] ?? intent.objective
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "launchApp", app: bundleID)),
                metadata: metadata
            )
        }

        if objective.contains("url") || objective.contains("http") || objective.contains("website") {
            let urlString = intent.metadata["url"] ?? intent.objective
            return Command(
                type: .ui,
                payload: .ui(UIAction(name: "openURL", query: urlString)),
                metadata: metadata
            )
        }

        // Default: try to launch app
        let bundleID = intent.metadata["bundleID"] ?? intent.objective
        _ = context
        return Command(
            type: .ui,
            payload: .ui(UIAction(name: "launchApp", app: bundleID)),
            metadata: metadata
        )
    }

    private func decodeActionIntent(from intent: Intent) -> ActionIntent? {
        guard let encoded = intent.metadata["action_intent_base64"],
              let data = Data(base64Encoded: encoded)
        else {
            return nil
        }
        return try? JSONDecoder().decode(ActionIntent.self, from: data)
    }

    private func commandFrom(actionIntent: ActionIntent, fallbackIntent: Intent) -> Command {
        let source = fallbackIntent.metadata["source"] ?? "planner.action-intent"
        let metadata = CommandMetadata(
            intentID: fallbackIntent.id,
            source: source,
            traceTags: [actionIntent.agentKind.rawValue, actionIntent.action]
        )
        let normalizedApp: String? = {
            let trimmed = actionIntent.app.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "unknown" {
                return nil
            }
            return trimmed
        }()        // Note: actionIntent.codeCommand is a deprecated field. New code should use typed specs.
        if let codeCommand = actionIntent.codeCommand {
            let workspace = codeCommand.workspaceRoot
            let path = codeCommand.workspaceRelativePath ?? ""
            let content = actionIntent.text
            
            switch codeCommand.category {
            case .build:
                let spec = BuildSpec(workspaceRoot: workspace)
                return Command(type: .code, payload: .build(spec), metadata: metadata)
            case .test:
                let spec = TestSpec(workspaceRoot: workspace)
                return Command(type: .code, payload: .test(spec), metadata: metadata)
            case .editFile, .writeFile, .generatePatch:
                let spec = FileMutationSpec(path: path, operation: .write, content: content, workspaceRoot: workspace)
                return Command(type: .code, payload: .file(spec), metadata: metadata)
            case .gitStatus:
                let spec = GitSpec(operation: .status, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitCommit:
                let spec = GitSpec(operation: .commit, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitBranch:
                let spec = GitSpec(operation: .branch, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .gitPush:
                let spec = GitSpec(operation: .push, args: codeCommand.arguments, workspaceRoot: workspace)
                return Command(type: .code, payload: .git(spec), metadata: metadata)
            case .openFile:
                let action = CodeAction(name: "readFile", filePath: path, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            case .searchCode, .indexRepository:
                let action = CodeAction(name: "searchRepository", query: codeCommand.summary, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            default:
                let action = CodeAction(name: codeCommand.category.rawValue, query: codeCommand.summary, workspacePath: workspace)
                return Command(type: .code, payload: .code(action), metadata: metadata)
            }
        }

        let modifiers: [String]? = {
            if let explicit = actionIntent.modifiers {
                return explicit
            }
            guard (actionIntent.action == "press" || actionIntent.action == "hotkey"),
                  let encoded = actionIntent.role
            else {
                return nil
            }
            return encoded.split(separator: "+").map(String.init)
        }()

        let inferredAmount: Int? = {
            if let amount = actionIntent.amount {
                return amount
            }
            return actionIntent.action == "scroll" ? actionIntent.count : nil
        }()

        let uiAction = UIAction(
            name: actionIntent.action,
            app: normalizedApp,
            query: actionIntent.query,
            text: actionIntent.text,
            role: actionIntent.role,
            domID: actionIntent.domID,
            x: actionIntent.x,
            y: actionIntent.y,
            button: actionIntent.button,
            count: actionIntent.count,
            windowTitle: actionIntent.windowTitle,
            clear: actionIntent.clear,
            modifiers: modifiers,
            amount: inferredAmount,
            width: actionIntent.width,
            height: actionIntent.height
        )
        let isCode = actionIntent.agentKind == .code
        if isCode {
            return Command(type: CommandType.code, payload: .code(CodeAction(name: actionIntent.action, query: actionIntent.query)), metadata: metadata)
        }
        return Command(type: .ui, payload: .ui(uiAction), metadata: metadata)
    }
}
