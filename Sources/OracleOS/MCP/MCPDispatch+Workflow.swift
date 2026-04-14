import Foundation

// MCPDispatch+Workflow.swift — Workflow tool implementations.
//
// Workflow indexing here remains a bounded service-persistence surface.
// Persisted workflow plans are support material and do not redefine the main
// execution spine or commit authority.
//
// Covers: oracle_workflow_list, oracle_workflow_mine, oracle_workflow_execute

private struct WorkflowListItem: Encodable {
    let id: String
    let goalPattern: String
    let successRate: Double
    let stepCount: Int
    let parameterSlots: [String]
    let promotionStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case goalPattern = "goal_pattern"
        case successRate = "success_rate"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case promotionStatus = "promotion_status"
    }
}

private struct WorkflowListPayload: Encodable {
    let workflows: [WorkflowListItem]
    let count: Int
}

private struct WorkflowMineItem: Encodable {
    let id: String
    let goalPattern: String
    let successRate: Double
    let stepCount: Int
    let parameterSlots: [String]
    let promotionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case goalPattern = "goal_pattern"
        case successRate = "success_rate"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case promotionStatus = "promotion_status"
    }
}

private struct WorkflowMinePayload: Encodable {
    let synthesized: Int
    let workflows: [WorkflowMineItem]
}

struct WorkflowExecutionPayload: Encodable {
    let workflowID: String
    let goalPattern: String
    let executedStepID: String
    let executedStepIndex: Int
    let stepCount: Int
    let parameterSlots: [String]
    let parameters: [String: String]?
    let skill: String
    let domain: String
    let query: String?

    enum CodingKeys: String, CodingKey {
        case workflowID = "workflow_id"
        case goalPattern = "goal_pattern"
        case executedStepID = "executed_step_id"
        case executedStepIndex = "executed_step_index"
        case stepCount = "step_count"
        case parameterSlots = "parameter_slots"
        case parameters
        case skill
        case domain
        case query
    }
}

extension MCPDispatch {
    @MainActor
    static func dispatchWorkflow(
        _ request: MCPToolRequest,
        container: RuntimeContainer,
        runtime: RuntimeOrchestrator
    ) async -> ToolResult {
        switch request.name {

        case MCPToolName.workflowList:
            let index = WorkflowIndex()
            let plans = index.allPlans()
            let payload = WorkflowListPayload(
                workflows: plans.map { plan in
                    WorkflowListItem(
                        id: plan.id,
                        goalPattern: plan.goalPattern,
                        successRate: plan.successRate,
                        stepCount: plan.steps.count,
                        parameterSlots: plan.parameterSlots,
                        promotionStatus: plan.promotionStatus.rawValue
                    )
                },
                count: plans.count
            )
            return typedResult(payload)

        case MCPToolName.workflowMine:
            guard let goalPattern = request.string("goal_pattern") else {
                return ToolResult(
                    success: false,
                    error: "goal_pattern is required for \(MCPToolName.workflowMine)")
            }
            let limit = request.int("limit") ?? 1000
            let events = container.traceStore.loadRecentEvents(limit: limit)
            let synthesized = WorkflowSynthesizer().synthesize(
                goalPattern: goalPattern, events: events)
            if synthesized.isEmpty {
                return typedResult(
                    WorkflowMinePayload(synthesized: 0, workflows: []),
                    suggestion:
                        "No repeatable patterns found for '\(goalPattern)'. Run more successful traces to build workflow patterns."
                )
            }

            let index = WorkflowIndex()
            for plan in synthesized {
                index.add(plan)
            }
            let payload = WorkflowMinePayload(
                synthesized: synthesized.count,
                workflows: synthesized.map { plan in
                    WorkflowMineItem(
                        id: plan.id,
                        goalPattern: plan.goalPattern,
                        successRate: plan.successRate,
                        stepCount: plan.steps.count,
                        parameterSlots: plan.parameterSlots,
                        promotionStatus: nil
                    )
                }
            )
            return typedResult(
                payload,
                suggestion:
                    "Synthesized \(synthesized.count) workflow(s) and saved to index. Use oracle_workflow_list to see all."
            )

        case MCPToolName.workflowExecute:
            guard let workflowID = request.string("workflow_id") else {
                return ToolResult(
                    success: false,
                    error: "workflow_id is required for \(MCPToolName.workflowExecute)")
            }
            let index = WorkflowIndex()
            guard let plan = index.plan(id: workflowID) else {
                return ToolResult(
                    success: false,
                    error: "Workflow '\(workflowID)' not found.",
                    suggestion: "Use oracle_workflow_list to see available workflow IDs."
                )
            }
            return await executeWorkflowPlan(
                plan,
                request: request,
                container: container,
                runtime: runtime
            )

        default:
            return ToolResult(success: false, error: "Unknown workflow tool: \(request.name)")
        }
    }

    @MainActor
    static func executeWorkflowPlan(
        _ plan: WorkflowPlan,
        request: MCPToolRequest,
        container: RuntimeContainer,
        runtime: RuntimeOrchestrator
    ) async -> ToolResult {
        let parameters = workflowParameters(from: request)
        let snapshot = await container.commitCoordinator.snapshot()
        let workflowExecutor = WorkflowExecutor()

        guard
            let match = workflowExecutor.match(
                plan: plan,
                planningStateID: snapshot.planningStateID
            )
        else {
            return ToolResult(
                success: false,
                error:
                    "Workflow '\(plan.id)' has no step applicable to the current committed planning state.",
                suggestion:
                    "Run oracle_context or oracle_state to confirm the current runtime state before retrying this workflow."
            )
        }

        let step = match.plan.steps[match.stepIndex]
        let query = substituteWorkflowSlots(
            in: step.semanticQuery?.text ?? step.actionContract.targetLabel,
            parameters: parameters
        )
        let unresolvedSlots = unresolvedWorkflowSlots(in: [
            query,
            substituteWorkflowSlots(
                in: step.actionContract.workspaceRelativePath, parameters: parameters),
        ])
        if !unresolvedSlots.isEmpty {
            return ToolResult(
                success: false,
                error:
                    "Workflow '\(plan.id)' is missing parameter values for: \(unresolvedSlots.sorted().joined(separator: ", ")).",
                suggestion:
                    "Provide those names under the parameters object when calling oracle_workflow_execute."
            )
        }

        let workspaceRoot = snapshot.repositoryRoot ?? FileManager.default.currentDirectoryPath
        let appName = step.semanticQuery?.app ?? snapshot.activeApplication

        guard
            let actionIntent = workflowActionIntent(
                for: step,
                query: query,
                appName: appName,
                workspaceRoot: workspaceRoot,
                parameters: parameters
            )
        else {
            return ToolResult(
                success: false,
                error:
                    "Workflow step '\(step.actionContract.skillName)' cannot be reconstructed safely for runtime execution from the stored workflow contract.",
                suggestion:
                    "Use oracle_workflow_list to inspect this workflow, or mine a richer workflow/recipe that preserves explicit execution inputs."
            )
        }

        let plannerDecision = workflowExecutor.nextDecision(
            match: match,
            plannerFamily: plannerFamily(for: step.agentKind),
            sourceNotes: ["oracle_workflow_execute"]
        )
        let runtimeResult = RuntimeExecutionDriver(intentAPI: runtime, surface: .mcp).execute(
            intent: actionIntent,
            plannerDecision: plannerDecision,
            selectedCandidate: nil
        )

        let payload = WorkflowExecutionPayload(
            workflowID: plan.id,
            goalPattern: plan.goalPattern,
            executedStepID: step.id,
            executedStepIndex: match.stepIndex + 1,
            stepCount: plan.steps.count,
            parameterSlots: plan.parameterSlots,
            parameters: parameters.isEmpty ? nil : parameters,
            skill: step.actionContract.skillName,
            domain: step.actionContract.domain,
            query: query
        )

        guard let data = legacyDict(for: payload) else {
            return ToolResult(
                success: false, error: "Failed to serialize workflow execution result")
        }

        return ToolResult(
            success: runtimeResult.success,
            data: data,
            error: runtimeResult.error,
            suggestion: runtimeResult.suggestion,
            actionResult: runtimeResult.actionResult,
            traceResult: runtimeResult.traceResult,
            codeExecutionResult: runtimeResult.codeExecutionResult
        )
    }

    private static func workflowParameters(from request: MCPToolRequest) -> [String: String] {
        guard let object = request.objectValue("parameters") else {
            return [:]
        }

        var parameters: [String: String] = [:]
        for (key, value) in object {
            if let stringValue = value.stringValue {
                parameters[key] = stringValue
            } else if let intValue = value.intValue {
                parameters[key] = String(intValue)
            } else if let doubleValue = value.doubleValue {
                parameters[key] = String(doubleValue)
            } else if let boolValue = value.boolValue {
                parameters[key] = boolValue ? "true" : "false"
            }
        }
        return parameters
    }

    private static func substituteWorkflowSlots(
        in text: String?,
        parameters: [String: String]
    ) -> String? {
        guard var text else {
            return nil
        }

        let pattern = #"\{\{([A-Za-z0-9_\-]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges == 2,
                let fullRange = Range(match.range(at: 0), in: text),
                let keyRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            let key = String(text[keyRange])
            if let replacement = parameters[key] {
                text.replaceSubrange(fullRange, with: replacement)
            }
        }

        return text
    }

    private static func unresolvedWorkflowSlots(in texts: [String?]) -> Set<String> {
        let pattern = #"\{\{([A-Za-z0-9_\-]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var slots: Set<String> = []
        for text in texts.compactMap({ $0 }) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard match.numberOfRanges == 2,
                    let range = Range(match.range(at: 1), in: text)
                else {
                    continue
                }
                slots.insert(String(text[range]))
            }
        }
        return slots
    }

    private static func workflowActionIntent(
        for step: WorkflowStep,
        query: String?,
        appName: String?,
        workspaceRoot: String,
        parameters: [String: String]
    ) -> ActionIntent? {
        let skillName = step.actionContract.skillName
        let targetRole = step.actionContract.targetRole
        let workspaceRelativePath = substituteWorkflowSlots(
            in: step.actionContract.workspaceRelativePath,
            parameters: parameters
        )

        switch step.agentKind {
        case .os:
            return workflowOSActionIntent(
                skillName: skillName,
                query: query,
                targetRole: targetRole,
                appName: appName,
                parameters: parameters
            )
        case .code:
            return workflowCodeActionIntent(
                skillName: skillName,
                commandCategory: step.actionContract.commandCategory,
                query: query,
                workspaceRelativePath: workspaceRelativePath,
                workspaceRoot: workspaceRoot,
                parameters: parameters
            )
        }
    }

    private static func workflowOSActionIntent(
        skillName: String,
        query: String?,
        targetRole: String?,
        appName: String?,
        parameters: [String: String]
    ) -> ActionIntent? {
        switch skillName {
        case "click":
            return ActionIntent.click(app: appName, query: query, role: targetRole)
        case "type", "fill_form":
            guard let text = parameters["text"] ?? parameters["value"] else {
                return nil
            }
            return ActionIntent.type(
                app: appName,
                into: query,
                text: text,
                clear: workflowBoolParameter(["clear"], parameters: parameters) ?? false
            )
        case "focus", "open_application", "switch_window":
            let resolvedApp = parameters["app"] ?? query ?? appName
            guard let resolvedApp, !resolvedApp.isEmpty else {
                return nil
            }
            return ActionIntent.focus(
                app: resolvedApp,
                windowTitle: parameters["window_title"]
            )
        case "press":
            guard let query, !query.isEmpty else {
                return nil
            }
            let keys = query.split(separator: "+").map(String.init)
            let key = keys.last ?? query
            let modifiers = keys.count > 1 ? Array(keys.dropLast()) : nil
            return ActionIntent.press(app: appName, key: key, modifiers: modifiers)
        case "hotkey":
            guard let query, !query.isEmpty else {
                return nil
            }
            return ActionIntent.hotkey(
                app: appName, keys: query.split(separator: "+").map(String.init))
        case "scroll":
            let direction = parameters["direction"] ?? query
            guard let direction, !direction.isEmpty else {
                return nil
            }
            return ActionIntent.scroll(
                app: appName,
                direction: direction,
                amount: workflowIntParameter(["amount"], parameters: parameters)
            )
        case "read_file":
            return ActionIntent(
                agentKind: .os,
                app: appName ?? "Finder",
                name: "read file \(query ?? "")",
                action: "read-file",
                query: query,
                role: targetRole
            )
        default:
            return nil
        }
    }

    private static func workflowCodeActionIntent(
        skillName: String,
        commandCategory: String?,
        query: String?,
        workspaceRelativePath: String?,
        workspaceRoot: String,
        parameters: [String: String]
    ) -> ActionIntent? {
        guard
            let commandSpec = workflowCommandSpec(
                skillName: skillName,
                commandCategory: commandCategory,
                query: query,
                workspaceRelativePath: workspaceRelativePath,
                workspaceRoot: workspaceRoot,
                parameters: parameters
            )
        else {
            return nil
        }

        return ActionIntent.code(
            name: skillName,
            command: commandSpec,
            workspaceRelativePath: commandSpec.workspaceRelativePath,
            text: parameters["content"] ?? parameters["patch"] ?? parameters["text"]
        )
    }

    private static func workflowCommandSpec(
        skillName: String,
        commandCategory: String?,
        query: String?,
        workspaceRelativePath: String?,
        workspaceRoot: String,
        parameters: [String: String]
    ) -> CommandSpec? {
        let rawCategory = commandCategory ?? inferredWorkflowCommandCategory(for: skillName)
        guard let rawCategory,
            let category = CodeCommandCategory(rawValue: rawCategory)
        else {
            return nil
        }

        switch category {
        case .openFile:
            let path = workspaceRelativePath ?? query
            guard let path, !path.isEmpty else { return nil }
            return CommandSpec(
                category: .openFile,
                executable: "/usr/bin/env",
                arguments: [path],
                workspaceRoot: workspaceRoot,
                workspaceRelativePath: path,
                summary: "open \(path)"
            )
        case .searchCode:
            let resolvedQuery = query ?? parameters["query"]
            guard let resolvedQuery, !resolvedQuery.isEmpty else { return nil }
            return CommandSpec(
                category: .searchCode,
                executable: "/usr/bin/env",
                arguments: [resolvedQuery],
                workspaceRoot: workspaceRoot,
                summary: "search code for \(resolvedQuery)"
            )
        case .indexRepository:
            return CommandSpec(
                category: .indexRepository,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: workspaceRoot,
                summary: "index repository"
            )
        case .build:
            return CommandSpec(
                category: .build,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: workspaceRoot,
                summary: "build workspace"
            )
        case .test:
            return CommandSpec(
                category: .test,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: workspaceRoot,
                summary: "test workspace"
            )
        case .gitStatus:
            return CommandSpec(
                category: .gitStatus,
                executable: "/usr/bin/env",
                arguments: [],
                workspaceRoot: workspaceRoot,
                summary: "git status"
            )
        case .gitBranch:
            let branch = parameters["branch"] ?? query
            return CommandSpec(
                category: .gitBranch,
                executable: "/usr/bin/env",
                arguments: branch.map { [$0] } ?? [],
                workspaceRoot: workspaceRoot,
                summary: branch.map { "git branch \($0)" } ?? "git branch"
            )
        case .gitCommit:
            let message = parameters["message"] ?? parameters["commit_message"] ?? query
            return CommandSpec(
                category: .gitCommit,
                executable: "/usr/bin/env",
                arguments: message.map { ["-m", $0] } ?? [],
                workspaceRoot: workspaceRoot,
                summary: message.map { "git commit -m \($0)" } ?? "git commit"
            )
        case .gitPush:
            let remote = parameters["remote"]
            let branch = parameters["branch"] ?? query
            let arguments = [remote, branch].compactMap { $0 }
            return CommandSpec(
                category: .gitPush,
                executable: "/usr/bin/env",
                arguments: arguments,
                workspaceRoot: workspaceRoot,
                summary: arguments.isEmpty
                    ? "git push" : "git push \(arguments.joined(separator: " "))"
            )
        case .editFile, .writeFile, .generatePatch:
            let path = workspaceRelativePath ?? query
            guard let path, !path.isEmpty else { return nil }
            return CommandSpec(
                category: category,
                executable: "/usr/bin/env",
                arguments: [path],
                workspaceRoot: workspaceRoot,
                workspaceRelativePath: path,
                summary: "\(category.rawValue) \(path)"
            )
        case .formatter, .linter, .parseBuildFailure, .parseTestFailure:
            return CommandSpec(
                category: category,
                executable: "/usr/bin/env",
                arguments: workspaceRelativePath.map { [$0] } ?? [],
                workspaceRoot: workspaceRoot,
                workspaceRelativePath: workspaceRelativePath,
                summary: category.rawValue
            )
        }
    }

    private static func inferredWorkflowCommandCategory(for skillName: String) -> String? {
        switch skillName {
        case "readFile", "openFile":
            return CodeCommandCategory.openFile.rawValue
        case "searchRepository":
            return CodeCommandCategory.searchCode.rawValue
        case "indexRepository":
            return CodeCommandCategory.indexRepository.rawValue
        case "build":
            return CodeCommandCategory.build.rawValue
        case "test":
            return CodeCommandCategory.test.rawValue
        case "git-status":
            return CodeCommandCategory.gitStatus.rawValue
        case "git-branch":
            return CodeCommandCategory.gitBranch.rawValue
        case "git-commit":
            return CodeCommandCategory.gitCommit.rawValue
        case "git-push":
            return CodeCommandCategory.gitPush.rawValue
        case "edit-file":
            return CodeCommandCategory.editFile.rawValue
        case "write-file":
            return CodeCommandCategory.writeFile.rawValue
        case "generate-patch":
            return CodeCommandCategory.generatePatch.rawValue
        case "formatter":
            return CodeCommandCategory.formatter.rawValue
        case "linter":
            return CodeCommandCategory.linter.rawValue
        case "parse-build-failure":
            return CodeCommandCategory.parseBuildFailure.rawValue
        case "parse-test-failure":
            return CodeCommandCategory.parseTestFailure.rawValue
        default:
            return nil
        }
    }

    private static func plannerFamily(for agentKind: AgentKind) -> PlannerFamily {
        switch agentKind {
        case .code:
            return .code
        case .os:
            return .os
        }
    }

    private static func workflowIntParameter(
        _ keys: [String],
        parameters: [String: String]
    ) -> Int? {
        for key in keys {
            if let value = parameters[key], let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private static func workflowBoolParameter(
        _ keys: [String],
        parameters: [String: String]
    ) -> Bool? {
        for key in keys {
            guard
                let value = parameters[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            else {
                continue
            }
            switch value {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                continue
            }
        }
        return nil
    }
}
