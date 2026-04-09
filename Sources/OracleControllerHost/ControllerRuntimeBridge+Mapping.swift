// ControllerRuntimeBridge+Mapping.swift — Core model mapping helpers (private → internal for cross-file extension).

import AppKit
import Foundation
import OracleControllerShared
import OracleOS

struct ClaudeConfigDocument: Decodable {
    let mcpServers: [String: ClaudeMCPServer]?
}

struct ClaudeMCPServer: Decodable {}

extension ControllerRuntimeBridge {
    func mapActionResult(request: ActionRequest, result: ToolResult) -> ActionRunResult {
        let actionResult = result.actionResult
        let codeExecutionResult = result.codeExecutionResult
        let observation = ObservationBuilder.capture(appName: request.appName)

        return ActionRunResult(
            request: request,
            success: actionResult?.success ?? result.success,
            verified: actionResult?.verified ?? result.success,
            message: actionResult?.message ?? result.error ?? result.suggestion,
            failureClass: actionResult?.failureClass,
            verificationStatus: actionResult?.verificationStatus?.rawValue,
            method: actionResult?.method,
            elapsedMs: actionResult?.elapsedMs ?? 0,
            resultingObservation: map(observation),
            approvalRequestID: actionResult?.approvalRequestID,
            approvalStatus: actionResult?.approvalStatus,
            protectedOperation: actionResult?.protectedOperation,
            appProtectionProfile: actionResult?.appProtectionProfile,
            blockedByPolicy: actionResult?.blockedByPolicy ?? false,
            executedThroughExecutor: actionResult?.executedThroughExecutor ?? false,
            policyMode: actionResult?.policyDecision?.policyMode.rawValue,
            commandCategory: codeExecutionResult?.commandCategory,
            commandSummary: codeExecutionResult?.commandSummary,
            workspaceRelativePath: codeExecutionResult?.workspaceRelativePath,
            buildResultSummary: codeExecutionResult?.buildResultSummary,
            testResultSummary: codeExecutionResult?.testResultSummary,
            patchID: codeExecutionResult?.patchID
        )
    }

    func mapRecipeRunResult(recipeName: String, totalStepsFallback: Int, result: ToolResult) -> RecipeRunResultDocument {
        let recipeRunResult = result.recipeRunResult

        let stepResults = (recipeRunResult?.stepResults ?? []).map { stepResult in
            RecipeRunStepResult(
                id: stepResult.stepIndex,
                action: stepResult.action,
                success: stepResult.success,
                durationMs: stepResult.durationMs,
                error: stepResult.error,
                note: stepResult.note
            )
        }

        return RecipeRunResultDocument(
            recipeName: recipeRunResult?.recipeName ?? recipeName,
            success: result.success,
            stepsCompleted: recipeRunResult?.stepsCompleted ?? 0,
            totalSteps: recipeRunResult?.totalSteps ?? totalStepsFallback,
            error: result.error,
            traceSessionID: sessionID,
            stepResults: stepResults,
            paused: recipeRunResult?.pendingApproval == true,
            pendingApprovalRequestID: recipeRunResult?.approvalRequestID,
            resumeToken: recipeRunResult?.resumeToken
        )
    }

    func screenshotFrame(appName: String?) -> ScreenshotFrame? {
        let result = AXScanner.screenshot(appName: appName, fullResolution: false)
        guard result.success,
              let screenshot = result.screenshotResult
        else {
            return nil
        }

        return ScreenshotFrame(
            base64PNG: screenshot.base64PNG,
            width: screenshot.width,
            height: screenshot.height,
            windowTitle: screenshot.windowTitle
        )
    }

    func loadClaudeConfig() -> ClaudeConfigDocument? {
        let configPath = NSHomeDirectory() + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return nil
        }
        return try? ControllerJSONCoding.makeDecoder().decode(ClaudeConfigDocument.self, from: data)
    }

    func map(_ observation: Observation) -> ObservationSnapshot {
        ObservationSnapshot(
            timestamp: observation.timestamp,
            appName: observation.app,
            windowTitle: observation.windowTitle,
            url: observation.url,
            focusedElementID: observation.focusedElementID,
            elements: observation.elements.map(map)
        )
    }

    func map(_ element: UnifiedElement) -> ElementSnapshot {
        ElementSnapshot(
            id: element.id,
            source: element.source.rawValue,
            role: element.role,
            label: element.label,
            value: element.value,
            frame: element.frame.map {
                ElementFrameSnapshot(
                    x: $0.origin.x,
                    y: $0.origin.y,
                    width: $0.width,
                    height: $0.height
                )
            },
            enabled: element.enabled,
            visible: element.visible,
            focused: element.focused,
            confidence: element.confidence
        )
    }

    func map(_ recipe: Recipe) -> RecipeDocument {
        let encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let rawJSON: String?
        if let encoded = try? encoder.encode(recipe) {
            rawJSON = String(data: encoded, encoding: .utf8)
        } else {
            rawJSON = nil
        }
        let params = recipe.params?.reduce(into: [String: RecipeParamDocument]()) { partialResult, entry in
            partialResult[entry.key] = RecipeParamDocument(
                id: entry.key,
                type: entry.value.type,
                description: entry.value.description,
                required: entry.value.required ?? false
            )
        }

        return RecipeDocument(
            schemaVersion: recipe.schemaVersion,
            name: recipe.name,
            description: recipe.description,
            app: recipe.app,
            params: params,
            preconditions: recipe.preconditions.map {
                RecipePreconditionsDocument(
                    appRunning: $0.appRunning,
                    urlContains: $0.urlContains
                )
            },
            steps: recipe.steps.map { step in
                RecipeStepDocument(
                    id: step.id,
                    action: step.action,
                    target: step.target.map(map),
                    params: step.params,
                    waitAfter: step.waitAfter.map { wait in
                        RecipeWaitConditionDocument(
                            condition: wait.condition,
                            target: wait.target.map(map),
                            value: wait.value,
                            timeout: wait.timeout
                        )
                    },
                    note: step.note,
                    onFailure: step.onFailure
                )
            },
            onFailure: recipe.onFailure,
            rawJSON: rawJSON
        )
    }

    func map(_ document: RecipeDocument) throws -> Recipe {
        Recipe(
            schemaVersion: document.schemaVersion,
            name: document.name,
            description: document.description,
            app: document.app,
            params: document.params?.mapValues(map),
            preconditions: document.preconditions.map(map),
            steps: document.steps.map(map),
            onFailure: document.onFailure
        )
    }

    func map(_ locator: Locator) -> LocatorDocument {
        LocatorDocument(
            criteria: locator.criteria.map {
                CriterionDocument(
                    attribute: $0.attribute,
                    value: $0.value,
                    matchType: $0.matchType?.rawValue
                )
            },
            computedNameContains: locator.computedNameContains
        )
    }

    func map(_ document: LocatorDocument) -> Locator {
        Locator(
            criteria: document.criteria.map { criterion in
                Criterion(
                    attribute: criterion.attribute,
                    value: criterion.value,
                    matchType: JSONPathHintComponent.MatchType(rawValue: criterion.matchType ?? "exact") ?? .exact
                )
            },
            computedNameContains: document.computedNameContains
        )
    }

    func map(_ document: RecipeParamDocument) -> RecipeParam {
        RecipeParam(
            type: document.type,
            description: document.description,
            required: document.required
        )
    }

    func map(_ document: RecipePreconditionsDocument) -> RecipePreconditions {
        RecipePreconditions(
            appRunning: document.appRunning,
            urlContains: document.urlContains
        )
    }

    func map(_ document: RecipeStepDocument) -> RecipeStep {
        RecipeStep(
            id: document.id,
            action: document.action,
            target: document.target.map(map),
            params: document.params,
            waitAfter: document.waitAfter.map(map),
            note: document.note,
            onFailure: document.onFailure
        )
    }

    func map(_ document: RecipeWaitConditionDocument) -> RecipeWaitCondition {
        RecipeWaitCondition(
            condition: document.condition,
            target: document.target.map(map),
            value: document.value,
            timeout: document.timeout
        )
    }

    func map(_ approval: ApprovalRequest) -> ApprovalRequestDocument {
        ApprovalRequestDocument(
            id: approval.id,
            createdAt: approval.createdAt,
            surface: approval.surface.rawValue,
            toolName: approval.toolName,
            appName: approval.appName,
            displayTitle: approval.displayTitle,
            reason: approval.reason,
            riskLevel: approval.riskLevel.rawValue,
            protectedOperation: approval.protectedOperation.rawValue,
            status: approval.status.rawValue,
            appProtectionProfile: approval.appProtectionProfile.rawValue
        )
    }
}
