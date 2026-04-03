// ControllerRuntimeBridge+Mapping.swift — Core model mapping helpers (private → internal for cross-file extension).

import AppKit
import Foundation
import OracleControllerShared
import OracleOS

extension ControllerRuntimeBridge {
    func mapActionResult(request: ActionRequest, result: ToolResult) -> ActionRunResult {
        let actionData = result.data?[ActionResultKey.actionResult] as? [String: Any]
        let traceData = result.data?[ActionResultKey.trace] as? [String: Any]
        let codeData = result.data?[ActionResultKey.codeExecution] as? [String: Any]
        let method = (actionData?[ActionResultKey.method] as? String) ?? (result.data?[ActionResultKey.method] as? String)
        let observation = ObservationBuilder.capture(appName: request.appName)
        let elapsedMs = (actionData?[ActionResultKey.elapsedMs] as? Double)
            ?? Double(actionData?[ActionResultKey.elapsedMs] as? Int ?? 0)

        return ActionRunResult(
            request: request,
            success: actionData?[ActionResultKey.success] as? Bool ?? result.success,
            verified: actionData?[ActionResultKey.verified] as? Bool ?? result.success,
            message: (actionData?[ActionResultKey.message] as? String) ?? result.error ?? result.suggestion,
            failureClass: actionData?[ActionResultKey.failureClass] as? String,
            method: method,
            elapsedMs: elapsedMs,
            resultingObservation: map(observation),
            approvalRequestID: actionData?[ActionResultKey.approvalRequestID] as? String ?? result.data?[ActionResultKey.approvalRequestID] as? String,
            approvalStatus: actionData?[ActionResultKey.approvalStatus] as? String ?? result.data?[ActionResultKey.approvalStatus] as? String,
            protectedOperation: actionData?[ActionResultKey.protectedOperation] as? String,
            appProtectionProfile: actionData?[ActionResultKey.appProtectionProfile] as? String,
            blockedByPolicy: actionData?[ActionResultKey.blockedByPolicy] as? Bool ?? false,
            policyMode: (actionData?[ActionResultKey.policyDecision] as? [String: Any])?["policy_mode"] as? String,
            commandCategory: codeData?[CodeExecutionResultKey.commandCategory] as? String,
            commandSummary: codeData?[CodeExecutionResultKey.commandSummary] as? String,
            workspaceRelativePath: codeData?[CodeExecutionResultKey.workspaceRelativePath] as? String,
            buildResultSummary: codeData?[CodeExecutionResultKey.buildResultSummary] as? String,
            testResultSummary: codeData?[CodeExecutionResultKey.testResultSummary] as? String,
            patchID: codeData?[CodeExecutionResultKey.patchID] as? String
        )
    }

    func mapRecipeRunResult(recipeName: String, totalStepsFallback: Int, result: ToolResult) -> RecipeRunResultDocument {
        let data = result.data ?? [:]
        let stepsCompleted = data[RecipeResultKey.stepsCompleted] as? Int ?? 0
        let totalSteps = data[RecipeResultKey.totalSteps] as? Int ?? totalStepsFallback
        let stepResults = (data[RecipeResultKey.stepResults] as? [[String: Any]] ?? []).map { stepData in
            RecipeRunStepResult(
                id: stepData[RecipeResultKey.stepIndex] as? Int ?? 0,
                action: stepData[RecipeResultKey.stepAction] as? String ?? "step",
                success: stepData[RecipeResultKey.stepSuccess] as? Bool ?? false,
                durationMs: stepData[RecipeResultKey.stepDurationMs] as? Int ?? 0,
                error: stepData[RecipeResultKey.stepError] as? String,
                note: stepData[RecipeResultKey.stepNote] as? String
            )
        }

        return RecipeRunResultDocument(
            recipeName: recipeName,
            success: result.success,
            stepsCompleted: stepsCompleted,
            totalSteps: totalSteps,
            error: result.error,
            traceSessionID: sessionID,
            stepResults: stepResults,
            paused: (data[RecipeResultKey.pendingApproval] as? Bool) == true,
            pendingApprovalRequestID: data[ActionResultKey.approvalRequestID] as? String,
            resumeToken: data[RecipeResultKey.resumeToken] as? String
        )
    }

    func screenshotFrame(appName: String?) -> ScreenshotFrame? {
        let result = AXScanner.screenshot(appName: appName, fullResolution: false)
        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String,
              let width = data["width"] as? Int,
              let height = data["height"] as? Int
        else {
            return nil
        }

        return ScreenshotFrame(
            base64PNG: base64,
            width: width,
            height: height,
            windowTitle: data["window_title"] as? String
        )
    }

    func loadClaudeConfig() -> [String: Any]? {
        let configPath = NSHomeDirectory() + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
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
        let data = try JSONSerialization.data(
            withJSONObject: recipeDictionary(from: document),
            options: [.prettyPrinted, .sortedKeys]
        )
        return try ControllerJSONCoding.makeDecoder().decode(Recipe.self, from: data)
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

    func recipeDictionary(from document: RecipeDocument) -> [String: Any] {
        var result: [String: Any] = [
            "schema_version": document.schemaVersion,
            "name": document.name,
            "description": document.description,
            "steps": document.steps.map(recipeStepDictionary),
        ]

        if let app = document.app, !app.isEmpty {
            result["app"] = app
        }
        if let params = document.params, !params.isEmpty {
            result["params"] = Dictionary(uniqueKeysWithValues: params.map { key, value in
                (
                    key,
                    [
                        "type": value.type,
                        "description": value.description,
                        "required": value.required,
                    ] as [String: Any]
                )
            })
        }
        if let preconditions = document.preconditions {
            var preconditionsDict: [String: Any] = [:]
            if let appRunning = preconditions.appRunning, !appRunning.isEmpty {
                preconditionsDict["app_running"] = appRunning
            }
            if let urlContains = preconditions.urlContains, !urlContains.isEmpty {
                preconditionsDict["url_contains"] = urlContains
            }
            if !preconditionsDict.isEmpty {
                result["preconditions"] = preconditionsDict
            }
        }
        if let onFailure = document.onFailure, !onFailure.isEmpty {
            result["on_failure"] = onFailure
        }

        return result
    }

    func recipeStepDictionary(from step: RecipeStepDocument) -> [String: Any] {
        var result: [String: Any] = [
            "id": step.id,
            "action": step.action,
        ]

        if let target = step.target {
            result["target"] = locatorDictionary(from: target)
        }
        if let params = step.params, !params.isEmpty {
            result["params"] = params
        }
        if let waitAfter = step.waitAfter {
            result["wait_after"] = waitDictionary(from: waitAfter)
        }
        if let note = step.note, !note.isEmpty {
            result["note"] = note
        }
        if let onFailure = step.onFailure, !onFailure.isEmpty {
            result["on_failure"] = onFailure
        }

        return result
    }

    func waitDictionary(from wait: RecipeWaitConditionDocument) -> [String: Any] {
        var result: [String: Any] = [
            "condition": wait.condition,
        ]
        if let target = wait.target {
            result["target"] = locatorDictionary(from: target)
        }
        if let value = wait.value, !value.isEmpty {
            result["value"] = value
        }
        if let timeout = wait.timeout {
            result["timeout"] = timeout
        }
        return result
    }

    func locatorDictionary(from locator: LocatorDocument) -> [String: Any] {
        var result: [String: Any] = [
            "criteria": locator.criteria.map { criterion in
                var dictionary: [String: Any] = [
                    "attribute": criterion.attribute,
                    "value": criterion.value,
                ]
                if let matchType = criterion.matchType, !matchType.isEmpty {
                    dictionary["matchType"] = matchType
                }
                return dictionary
            },
        ]
        if let computedNameContains = locator.computedNameContains, !computedNameContains.isEmpty {
            result["computedNameContains"] = computedNameContains
        }
        return result
    }
}
