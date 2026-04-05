// ControllerStore+Recipes.swift — Recipe library, editor, and run operations.

import Foundation
import OracleControllerShared

extension ControllerStore {
    func loadRecipes() async {
        do {
            let response = try await send(.init(command: .listRecipes))
            applyRecipesResponse(response)
        } catch {
            present(error)
        }
    }

    func selectRecipe(named name: String) async {
        do {
            let response = try await send(.init(command: .loadRecipe, recipeName: name))
            _ = applyRecipeResponse(response, requestedName: name)
        } catch {
            present(error)
        }
    }

    func createRecipe() {
        let baseName = "untitled-recipe-\(Int(Date().timeIntervalSince1970))"
        draftRecipe = RecipeDocument(
            name: baseName,
            description: "Describe the workflow.",
            app: snapshot?.observation.appName,
            params: [:],
            preconditions: RecipePreconditionsDocument(appRunning: snapshot?.observation.appName),
            steps: [RecipeStepDocument(id: 1, action: "focus")]
        )
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeRunParameters = [:]
        recipeEditorMode = .form
        selectedSection = .recipes
    }

    func duplicateSelectedRecipe() {
        var copy = draftRecipe
        copy.name = "\(draftRecipe.name)-copy"
        copy.rawJSON = nil
        draftRecipe = copy
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeEditorMode = .form
    }

    func addRecipeStep() {
        let nextID = (draftRecipe.steps.map(\.id).max() ?? 0) + 1
        draftRecipe.steps.append(RecipeStepDocument(id: nextID, action: "click"))
    }

    func removeRecipeStep(id: Int) {
        draftRecipe.steps.removeAll { $0.id == id }
        if draftRecipe.steps.isEmpty {
            addRecipeStep()
        }
    }

    func addRecipeParam() {
        let nextIndex = (draftRecipe.params?.count ?? 0) + 1
        let name = "param\(nextIndex)"
        var params = draftRecipe.params ?? [:]
        params[name] = RecipeParamDocument(id: name, type: "string", description: "Parameter", required: true)
        draftRecipe.params = params
    }

    func removeRecipeParam(id: String) {
        draftRecipe.params?.removeValue(forKey: id)
    }

    func saveDraftRecipe() async {
        if recipeEditorMode == .raw {
            if rawRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Raw recipe JSON is empty."
                return
            }
            draftRecipe.rawJSON = rawRecipeText
        } else {
            draftRecipe.rawJSON = nil
        }

        if let validationError = validateDraftRecipe() {
            errorMessage = validationError
            return
        }

        do {
            let response = try await send(.init(command: .saveRecipe, recipe: draftRecipe))
            guard let recipe = response.recipe else {
                errorMessage = response.errorMessage ?? "Save failed"
                return
            }
            inlineMessage = "Saved \(recipe.name)"
            await loadRecipes()
            apply(recipe: recipe)
        } catch {
            present(error)
        }
    }

    func deleteSelectedRecipe() async {
        guard let selectedRecipeName else { return }
        do {
            let response = try await send(.init(command: .deleteRecipe, recipeName: selectedRecipeName))
            guard response.acknowledged else {
                errorMessage = response.errorMessage ?? "Delete failed"
                return
            }
            inlineMessage = "Deleted \(selectedRecipeName)"
            await loadRecipes()
            createRecipe()
        } catch {
            present(error)
        }
    }

    func runSelectedRecipe() async {
        let recipeName = selectedRecipeName ?? draftRecipe.name
        let params = recipeRunParameters.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }

        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .runRecipe, recipeName: recipeName, recipeParams: params))
            guard requireAcknowledged(response, fallback: "Recipe run failed") else {
                return
            }
            if let recipeRun = response.recipeRun {
                recordRecipeRun(recipeRun, approvals: response.approvals)
                await loadTraceSessions()
                if let traceSessionID = recipeRun.traceSessionID {
                    await loadTraceSession(id: traceSessionID)
                }
                await loadDiagnostics()
            } else {
                latestRecipeRun = nil
                errorMessage = response.errorMessage ?? "Recipe run failed"
            }
        } catch {
            present(error)
        }
    }
}
