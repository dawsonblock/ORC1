import Foundation

// MCPDispatch+Recipes.swift — Recipe tool implementations.
//
// Covers: oracle_recipes, oracle_run, oracle_recipe_show,
//         oracle_recipe_save, oracle_recipe_delete

extension MCPDispatch {
    @MainActor
    static func dispatchRecipes(
        _ request: MCPToolRequest,
        runtime: RuntimeOrchestrator
    ) -> ToolResult {
        switch request.name {

        case "oracle_recipes":
            let recipes = RecipeStore.listRecipes()
            let summaries: [[String: Any]] = recipes.map { r in
                var d: [String: Any] = ["name": r.name, "description": r.description]
                if let params = r.params, !params.isEmpty {
                    d["parameters"] = Array(params.keys).sorted()
                }
                return d
            }
            return ToolResult(success: true, data: ["recipes": summaries, "count": summaries.count])

        case "oracle_run":
            if let resumeToken = request.string("resume_token") {
                return RecipeEngine.resume(
                    resumeToken: resumeToken,
                    approvalRequestID: request.string("approval_request_id"),
                    runtime: runtime
                )
            }
            guard let recipeName = request.string("recipe") else {
                return ToolResult(success: false, error: "recipe is required for oracle_run")
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
               let paramsDict = paramsValue.objectValue {
                for (k, v) in paramsDict {
                    if let s = v.stringValue { params[k] = s }
                }
            }
            return RecipeEngine.run(recipe: recipe, params: params, runtime: runtime)

        case "oracle_recipe_show":
            guard let name = request.string("name") else {
                return ToolResult(success: false, error: "name is required for oracle_recipe_show")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(success: false, error: "Recipe '\(name)' not found")
            }
            let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
            guard let data = try? encoder.encode(recipe),
                  let jsonStr = String(data: data, encoding: .utf8) else {
                return ToolResult(success: false, error: "Failed to serialize recipe '\(name)'")
            }
            return ToolResult(success: true, data: ["name": name, "recipe": jsonStr])

        case "oracle_recipe_save":
            guard let jsonStr = request.string("recipe_json") else {
                return ToolResult(success: false, error: "recipe_json is required for oracle_recipe_save")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonStr)
                return ToolResult(
                    success: true,
                    data: ["saved": name],
                    suggestion: "Recipe '\(name)' saved. Use oracle_run to execute it."
                )
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case "oracle_recipe_delete":
            guard let name = request.string("name") else {
                return ToolResult(success: false, error: "name is required for oracle_recipe_delete")
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
