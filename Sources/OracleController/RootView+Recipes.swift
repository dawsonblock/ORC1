// RootView+Recipes.swift — Recipe library, editor, and inspector views.

import AppKit
import Foundation
import SwiftUI
import OracleControllerShared

struct RecipesWorkspaceView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        HStack(alignment: .top, spacing: layout.stackSpacing) {
            PanelCard("Recipe Library", subtitle: "Replayable workflows with schema-backed editing", style: .hero) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricTile(
                        label: "Recipes",
                        value: "\(store.filteredRecipes.count)",
                        detail: "\(store.recipes.count) total saved workflows",
                        tone: .neutral
                    )
                    MetricTile(
                        label: "Editor",
                        value: store.selectedRecipeName ?? "Draft",
                        detail: store.recipeEditorMode == .raw ? "Raw JSON mode" : "Structured form mode",
                        tone: store.selectedRecipeName == nil ? .warning : .good
                    )
                }

                HStack(spacing: 10) {
                    TextField("Search recipes", text: $store.recipeSearchText)
                        .textFieldStyle(.roundedBorder)

                    Button("New") {
                        store.createRecipe()
                    }
                    .buttonStyle(ControllerPrimaryButtonStyle())
                }

                if store.filteredRecipes.isEmpty {
                    EmptyStateView(
                        systemImage: "square.stack.3d.up.slash",
                        title: "No Recipes Found",
                        message: "Create a workflow or clear the search filter to browse the full library."
                    )
                    .frame(minHeight: 420)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.filteredRecipes, id: \.name) { recipe in
                                Button {
                                    Task { await store.selectRecipe(named: recipe.name) }
                                } label: {
                                    RecipeLibraryRow(
                                        recipe: recipe,
                                        isSelected: store.selectedRecipeName == recipe.name
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 420)
                }

                HStack(spacing: 10) {
                    Button("Duplicate") {
                        store.duplicateSelectedRecipe()
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())
                    .disabled(store.selectedRecipeName == nil)

                    Button("Delete", role: .destructive) {
                        Task { await store.deleteSelectedRecipe() }
                    }
                    .buttonStyle(ControllerSecondaryButtonStyle())
                    .disabled(store.selectedRecipeName == nil)
                }
            }
            .frame(width: layout.railPanelWidth)

            RecipeEditorView(store: store)
                .frame(maxWidth: .infinity)
        }
        .padding(layout.workspacePaddingValue)
    }
}

struct RecipeEditorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        PanelCard("Recipe Editor", subtitle: "Form editing over the current JSON schema", style: .hero) {
            HStack {
                Picker("Mode", selection: $store.recipeEditorMode) {
                    ForEach(RecipeEditorMode.allCases) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button {
                    Task { await store.saveDraftRecipe() }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(ControllerPrimaryButtonStyle())
            }

            Text(editorHint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ControllerTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if store.recipeEditorMode == .raw {
                TextEditor(text: $store.rawRecipeText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 520)
                    .padding(10)
                    .background(ControllerTheme.panelRaised.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ControllerTheme.border, lineWidth: 1)
                    )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Recipe name", text: $store.draftRecipe.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Description", text: $store.draftRecipe.description)
                            .textFieldStyle(.roundedBorder)
                        TextField("App", text: stringBinding($store.draftRecipe.app))
                            .textFieldStyle(.roundedBorder)
                        TextField("Global failure policy", text: stringBinding($store.draftRecipe.onFailure))
                            .textFieldStyle(.roundedBorder)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Parameters")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Param") {
                                    store.addRecipeParam()
                                }
                                .buttonStyle(ControllerSecondaryButtonStyle())
                            }

                            if let paramKeys = store.draftRecipe.params?.keys.sorted(), !paramKeys.isEmpty {
                                ForEach(paramKeys, id: \.self) { key in
                                    RecipeParameterRow(store: store, paramKey: key)
                                }
                            } else {
                                Text("No parameters defined.")
                                    .foregroundStyle(ControllerTheme.muted)
                            }
                        }
                        .padding(14)
                        .background(ControllerTheme.panelRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Steps")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Button("Add Step") {
                                    store.addRecipeStep()
                                }
                                .buttonStyle(ControllerSecondaryButtonStyle())
                            }

                            ForEach(Array(store.draftRecipe.steps.enumerated()), id: \.element.id) { index, step in
                                RecipeStepCard(store: store, stepIndex: index, step: step)
                            }
                        }
                        .padding(14)
                        .background(ControllerTheme.panelRaised.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.trailing, 4)
                }
                .frame(minHeight: 520)
            }
        }
    }

    private var editorHint: String {
        if store.recipeEditorMode == .raw {
            return "Raw mode exposes the full JSON document when you need advanced locators or direct schema edits."
        }
        return "Structured mode keeps the most common workflow fields readable while preserving the same saved schema."
    }
}

private struct RecipeLibraryRow: View {
    let recipe: RecipeDocument
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ControllerTheme.ink)
                    Text(recipe.description)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ControllerTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                StatusBadge(label: "\(recipe.steps.count) steps", tone: .neutral)
            }

            HStack(spacing: 8) {
                if let app = recipe.app, !app.isEmpty {
                    StatusBadge(label: app, tone: .good)
                }
                if let onFailure = recipe.onFailure, !onFailure.isEmpty {
                    StatusBadge(label: onFailure, tone: .warning)
                }
            }
        }
        .padding(12)
        .background(isSelected ? ControllerTheme.accent.opacity(0.12) : ControllerTheme.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? ControllerTheme.accent.opacity(0.42) : ControllerTheme.border, lineWidth: 1)
        )
    }
}

struct RecipeParameterRow: View {
    @Bindable var store: ControllerStore
    let paramKey: String

    var body: some View {
        let paramBinding = Binding<RecipeParamDocument>(
            get: { store.draftRecipe.params?[paramKey] ?? RecipeParamDocument(id: paramKey, type: "string", description: "", required: true) },
            set: { updated in
                var params = store.draftRecipe.params ?? [:]
                params[paramKey] = updated
                store.draftRecipe.params = params
            }
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(paramKey)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeParam(id: paramKey)
                }
                .buttonStyle(ControllerSecondaryButtonStyle())
            }
            TextField("Type", text: paramBinding.type)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: paramBinding.description)
                .textFieldStyle(.roundedBorder)
            Toggle("Required", isOn: paramBinding.required)
        }
        .padding(12)
        .background(ControllerTheme.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct RecipeStepCard: View {
    @Bindable var store: ControllerStore
    let stepIndex: Int
    let step: RecipeStepDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(step.id)")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove", role: .destructive) {
                    store.removeRecipeStep(id: step.id)
                }
                .buttonStyle(ControllerSecondaryButtonStyle())
            }

            TextField("Action", text: binding(\.action))
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: stringBinding(binding(\.note)))
                .textFieldStyle(.roundedBorder)
            TextField("Failure policy", text: stringBinding(binding(\.onFailure)))
                .textFieldStyle(.roundedBorder)
            TextField(
                "Target contains (advanced locators remain available in raw mode)",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].target?.computedNameContains ?? "" },
                    set: { newValue in
                        var target = store.draftRecipe.steps[stepIndex].target ?? LocatorDocument()
                        target.computedNameContains = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].target = target
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after condition",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.condition ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: newValue)
                        waitAfter.condition = newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = newValue.isEmpty ? nil : waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            TextField(
                "Wait after value",
                text: Binding(
                    get: { store.draftRecipe.steps[stepIndex].waitAfter?.value ?? "" },
                    set: { newValue in
                        var waitAfter = store.draftRecipe.steps[stepIndex].waitAfter ?? RecipeWaitConditionDocument(condition: "elementExists")
                        waitAfter.value = newValue.isEmpty ? nil : newValue
                        store.draftRecipe.steps[stepIndex].waitAfter = waitAfter
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(ControllerTheme.panel.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RecipeStepDocument, Value>) -> Binding<Value> {
        Binding(
            get: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] },
            set: { store.draftRecipe.steps[stepIndex][keyPath: keyPath] = $0 }
        )
    }
}

struct RecipeInspectorView: View {
    @Bindable var store: ControllerStore
    @Environment(ControllerLayoutSettings.self) private var layout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                PanelCard("Run Recipe", subtitle: "Execute the selected workflow with explicit parameters") {
                    if let params = store.draftRecipe.params, !params.isEmpty {
                        ForEach(params.keys.sorted(), id: \.self) { key in
                            TextField(
                                key,
                                text: Binding(
                                    get: { store.recipeRunParameters[key] ?? "" },
                                    set: { store.recipeRunParameters[key] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Text("This recipe does not declare any runtime parameters.")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await store.runSelectedRecipe() }
                    } label: {
                        Label("Run Selected Recipe", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ControllerPrimaryButtonStyle())
                }

                PanelCard("Last Run", subtitle: "Structured replay results") {
                    if let latestRecipeRun = store.latestRecipeRun {
                        HStack {
                            StatusBadge(
                                label: latestRecipeRun.statusLabel,
                                tone: latestRecipeRun.paused ? .warning : (latestRecipeRun.success ? .good : .danger)
                            )
                            Text("\(latestRecipeRun.stepsCompleted)/\(latestRecipeRun.totalSteps) steps")
                                .font(.system(size: 12, design: .monospaced))
                        }
                        Text(latestRecipeRun.summaryText)
                            .font(.system(size: 11))
                            .foregroundStyle(ControllerTheme.muted)
                        if let pendingApprovalRequestID = latestRecipeRun.pendingApprovalRequestID {
                            KVRow(key: "Pending Approval", value: pendingApprovalRequestID, monospaced: true)
                        }
                        if let resumeToken = latestRecipeRun.resumeToken {
                            KVRow(key: "Resume Token", value: resumeToken, monospaced: true)
                        }
                        if let error = latestRecipeRun.error {
                            Text(error)
                                .foregroundStyle(ControllerTheme.danger)
                        }
                        ForEach(latestRecipeRun.stepResults) { step in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.action)
                                        .font(.system(size: 12, weight: .semibold))
                                    if let note = step.note {
                                        Text(note)
                                            .font(.system(size: 11))
                                            .foregroundStyle(ControllerTheme.muted)
                                    }
                                }
                                Spacer()
                                Text("\(step.durationMs) ms")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "play.rectangle.on.rectangle",
                            title: "No Run Yet",
                            message: "Run a recipe to inspect structured results and linked trace output."
                        )
                        .frame(height: 220)
                    }
                }
            }
            .padding(layout.workspacePaddingValue)
        }
    }
}

func stringBinding(_ source: Binding<String?>, defaultValue: String = "") -> Binding<String> {
    Binding<String>(
        get: { source.wrappedValue ?? defaultValue },
        set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}
