import Foundation

// MCPDispatch+Recipes.swift — Recipe tool implementations.
//
// Covers: oracle_recipes, oracle_run, oracle_recipe_show,
//         oracle_recipe_save, oracle_recipe_delete

struct RecipeSummary: Encodable {
    let name: String
    let description: String
    let parameters: [String]?
}

struct RecipeSummaryPayload: Encodable {
    let recipes: [RecipeSummary]
    let count: Int
}

private struct RecipeShowPayload: Encodable {
    let name: String
    let recipe: String
}

private struct RecipeSavePayload: Encodable {
    let saved: String
}

extension MCPDispatch {
    @MainActor
    static func dispatchRecipes(
        _ request: MCPToolRequest,
        runtime: RuntimeOrchestrator
    ) -> ToolResult {
        switch request.name {

        case MCPToolName.recipes:
            let recipes = RecipeStore.listRecipes()
            let payload = RecipeSummaryPayload(
                recipes: recipes.map { recipe in
                    let parameters =
                        recipe.params.map { params in
                            let names = Array(params.keys).sorted()
                            return names.isEmpty ? nil : names
                        } ?? nil
                    return RecipeSummary(
                        name: recipe.name,
                        description: recipe.description,
                        parameters: parameters
                    )
                },
                count: recipes.count
            )
            return typedResult(payload)

        case MCPToolName.run:
            if let resumeToken = request.string("resume_token") {
                return RecipeEngine.resume(
                    resumeToken: resumeToken,
                    approvalRequestID: request.string("approval_request_id"),
                    runtime: runtime
                )
            }
            guard let recipeName = request.string("recipe") else {
                return ToolResult(
                    success: false, error: "recipe is required for \(MCPToolName.run)")
            }
            guard let recipe = RecipeStore.loadRecipe(named: recipeName) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(recipeName)' not found",
                    suggestion: "Use oracle_recipes to list available recipes."
                )
            }
            var params: [String: String] = [:]
            if let paramsValue = request.arguments.objectValue?["params"],
                let paramsDict = paramsValue.objectValue
            {
                for (key, value) in paramsDict {
                    if let stringValue = value.stringValue {
                        params[key] = stringValue
                    }
                }
            }
            return RecipeEngine.run(recipe: recipe, params: params, runtime: runtime)

        case MCPToolName.recipeShow:
            guard let name = request.string("name") else {
                return ToolResult(
                    success: false, error: "name is required for \(MCPToolName.recipeShow)")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(success: false, error: "Recipe '\(name)' not found")
            }
            let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [
                .prettyPrinted, .sortedKeys,
            ])
            guard let data = try? encoder.encode(recipe),
                let jsonString = String(data: data, encoding: .utf8)
            else {
                return ToolResult(success: false, error: "Failed to serialize recipe '\(name)'")
            }
            return typedResult(RecipeShowPayload(name: name, recipe: jsonString))

        case MCPToolName.recipeSave:
            guard let jsonString = request.string("recipe_json") else {
                return ToolResult(
                    success: false, error: "recipe_json is required for \(MCPToolName.recipeSave)")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonString)
                return typedResult(
                    RecipeSavePayload(saved: name),
                    suggestion: "Recipe '\(name)' saved. Use oracle_run to execute it."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case MCPToolName.recipeDelete:
            guard let name = request.string("name") else {
                return ToolResult(
                    success: false, error: "name is required for \(MCPToolName.recipeDelete)")
            }
            let deleted = RecipeStore.deleteRecipe(named: name)
            return ToolResult(
                success: deleted,
                error: deleted ? nil : "Recipe '\(name)' not found or could not be deleted"
            )

        default:
            return ToolResult(success: false, error: "Unknown recipe tool: \(request.name)")
        }
    }
}
