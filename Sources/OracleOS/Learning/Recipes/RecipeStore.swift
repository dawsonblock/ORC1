// RecipeStore.swift - File-based recipe storage
//
// BOUNDED SERVICE PERSISTENCE — NOT part of the main-path execution contract.
// Recipe definitions are user-owned support material persisted under the
// recipes directory, separate from commit-authoritative runtime state.
//
// Loads/saves/lists/deletes recipes from the user-owned Oracle OS recipes directory.
// Logs decode errors so broken recipes are visible, not silently skipped.

import Foundation

/// File-based recipe storage.
public enum RecipeStore {

    private static var recipesDir: String {
        OracleProductPaths.recipesDirectory.path
    }

    /// List all available recipes. Logs decode errors for broken recipe files.
    public static func listRecipes() -> [Recipe] {
        let fm = FileManager.default
        ensureDirectory()

        var recipes: [Recipe] = []
        guard let files = try? fm.contentsOfDirectory(atPath: recipesDir) else { return [] }

        let decoder = OracleJSONCoding.makeDecoder()
        for file in files where file.hasSuffix(".json") {
            let path = (recipesDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path) else { continue }
            do {
                let recipe = try decoder.decode(Recipe.self, from: data)
                recipes.append(recipe)
            } catch {
                // Log decode errors so broken recipes are visible
                Log.warn("Failed to decode recipe '\(file)': \(error)")
            }
        }

        return recipes.sorted { $0.name < $1.name }
    }

    /// Load a specific recipe by name. Returns nil with logged error if decode fails.
    public static func loadRecipe(named name: String) -> Recipe? {
        let path = (recipesDir as NSString).appendingPathComponent("\(name).json")
        guard let data = FileManager.default.contents(atPath: path) else {
            Log.info("Recipe '\(name)' not found at \(path)")
            return nil
        }
        do {
            return try OracleJSONCoding.makeDecoder().decode(Recipe.self, from: data)
        } catch {
            Log.error("Failed to decode recipe '\(name)': \(error)")
            return nil
        }
    }

    /// Save a recipe.
    public static func saveRecipe(_ recipe: Recipe) throws {
        ensureDirectory()
        let path = (recipesDir as NSString).appendingPathComponent("\(recipe.name).json")
        let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let data = try encoder.encode(recipe)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Delete a recipe by name.
    public static func deleteRecipe(named name: String) -> Bool {
        let path = (recipesDir as NSString).appendingPathComponent("\(name).json")
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Save a recipe from raw JSON string. Returns recipe name on success.
    /// Validates the JSON parses correctly before saving.
    public static func saveRecipeJSON(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw OracleError.invalidParameter("Invalid JSON string")
        }
        do {
            let recipe = try OracleJSONCoding.makeDecoder().decode(Recipe.self, from: data)
            try saveRecipe(recipe)
            return recipe.name
        } catch let decodingError as DecodingError {
            // Give the agent a helpful error message about what's wrong with the JSON
            let detail: String
            switch decodingError {
            case .keyNotFound(let key, let context):
                detail =
                    "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .typeMismatch(let type, let context):
                detail =
                    "Type mismatch: expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .valueNotFound(let type, let context):
                detail =
                    "Missing value of type \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case .dataCorrupted(let context):
                detail =
                    "Corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            @unknown default:
                detail = "\(decodingError)"
            }
            throw OracleError.invalidParameter("Recipe JSON decode error: \(detail)")
        }
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            atPath: recipesDir,
            withIntermediateDirectories: true
        )
    }
}
