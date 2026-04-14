# Baseline Repair Pass — Oracle OS

**Date:** 2025-08 → 2026-04-03  
**Status:** Historical pass complete  
**Scope:** Bounded 11-step pass to fix contract drift, monolith surfaces, and guard coverage.

> This file is a historical repair-pass record. Current repo truth lives in [../STATUS.md](../STATUS.md) and [PRODUCT_CONTRACT.md](PRODUCT_CONTRACT.md).
>
> All items below were resolved for that pass. See [archive/REPAIR_SUMMARY.md](archive/REPAIR_SUMMARY.md) for the archived completion record.

---

## 1. MCP Contract Gap (Critical)

30 tools are declared in `MCPTools.swift`. Before this pass only **8 were dispatched**;
the remaining 22 returned `"Unknown tool"` at runtime.

### Tools grouped by category

| # | Tool | Category | Was Handled? |
| --- | ------ | ---------- | -------------- |
| 1 | `oracle_screenshot` | Perception | ✅ |
| 2 | `oracle_context` | Perception | ✅ |
| 3 | `oracle_state` | Perception | ✅ |
| 4 | `oracle_find` | Perception | ✅ |
| 5 | `oracle_read` | Perception | ✅ |
| 6 | `oracle_inspect` | Perception | ❌ → Fixed |
| 7 | `oracle_element_at` | Perception | ❌ → Fixed |
| 8 | `oracle_click` | Actions | ✅ |
| 9 | `oracle_type` | Actions | ✅ |
| 10 | `oracle_press` | Actions | ❌ → Fixed |
| 11 | `oracle_hotkey` | Actions | ❌ → Fixed |
| 12 | `oracle_scroll` | Actions | ❌ → Fixed |
| 13 | `oracle_focus` | Actions | ❌ → Fixed |
| 14 | `oracle_window` | Actions | ❌ → Fixed |
| 15 | `oracle_wait` | Wait | ✅ |
| 16 | `oracle_parse_screen` | Vision | ❌ → Fixed |
| 17 | `oracle_ground` | Vision | ❌ → Fixed |
| 18 | `oracle_memory_query` | Memory | ❌ → Fixed |
| 19 | `oracle_memory_draft` | Memory | ❌ → Fixed |
| 20 | `oracle_experiment_search` | Experiments | ❌ → Fixed |
| 21 | `oracle_architecture_review` | Architecture | ❌ → Fixed |
| 22 | `oracle_candidate_review` | Architecture | ❌ → Fixed |
| 23 | `oracle_recipes` | Recipes | ❌ → Fixed |
| 24 | `oracle_run` | Recipes | ❌ → Fixed |
| 25 | `oracle_recipe_show` | Recipes | ❌ → Fixed |
| 26 | `oracle_recipe_save` | Recipes | ❌ → Fixed |
| 27 | `oracle_recipe_delete` | Recipes | ❌ → Fixed |
| 28 | `oracle_workflow_mine` | Workflows | ❌ → Fixed |
| 29 | `oracle_workflow_list` | Workflows | ❌ → Fixed |
| 30 | `oracle_workflow_execute` | Workflows | ❌ → Fixed |

### Backing implementations that exist (verified)

- Perception: `AXScanner.inspect()`, `AXScanner.elementAt()`  
- Actions: `Actions.pressKey()`, `Actions.hotkey()`, `Actions.scroll()`, `Actions.focusApp()`, `Actions.manageWindow()`  
- Vision: `VisionScanner.parseScreen()`, `VisionScanner.groundElement()`  
- Memory: `UnifiedMemoryStore.projectStore?.query()`, `recordArchitectureDecision()`, etc.  
- Experiments: `ExperimentManager.run()` (async, 600s timeout)  
- Architecture: `ArchitectureEngine.review()`, `reviewCandidatePatch()`  
- Recipes: `RecipeStore.listRecipes()`, `loadRecipe()`, `saveRecipeJSON()`, `deleteRecipe()`; `RecipeEngine.run()`, `resume()`  
- Workflows: `WorkflowIndex().allPlans()`, `WorkflowSynthesizer().synthesize()`, `WorkflowIndex().plan(id:)`

---

## 2. Execution Boundary Taxonomy (VerifiedExecutor overclaim)

`VerifiedExecutor.swift` header claims it is **"The ONLY layer allowed to produce side effects."**  
This is false. Verified side-effect producers that exist outside VerifiedExecutor:

| Component | Write type |
| ----------- | ----------- |
| `ApprovalStore` | SQLite db |
| `ExperienceStore` | JSON trace files |
| `TraceRecorder` | Trace JSON |
| `MetricsRecorder` | Metrics JSON |
| `GraphPersistence` | SQLite graph |
| `ProjectMemoryStore` | Markdown files |
| `RecipeStore` | JSON recipe files |
| `WorkflowIndex` | JSON workflow files |

**Fix:** Rewrite the header to accurately describe the three-tier taxonomy:  

1. **Gated writes** — user actions through `VerifiedExecutor` (approval-checked)  
2. **Service writes** — infrastructure persistence (telemetry, memory, graph)  
3. **Read-only** — perception (AX, vision)

---

## 3. mcp_boundary_guard.py

**Fix:** ✅ Rewrote `scripts/mcp_boundary_guard.py` to parse `MCPTools.swift` for all 30 declared tool names and compare against `MCPDispatch.swift` switch cases. Exits 1 on any gap, exits 0 (clean) in CI. Replaces the former trivial 12-line version.

---

## 4. File Size Monoliths (Pre-pass measurements → Post-pass results)

| File | Before | After | Files |
| ------ | -------- | ------- | ------- |
| `Sources/OracleController/RootView.swift` | 2228L | 166L | 8 (split to `+Onboarding`, `+Control`, `+Recipes`, `+Traces`, `+Diagnostics`, `+Health`, `+Settings`) |
| `Sources/OracleOS/Intent/Actions/Actions.swift` | 1226L | split | 7 action files |
| `Sources/OracleControllerHost/ControllerRuntimeBridge.swift` | 929L | 338L | 4 (`+Mapping`, `+DiagnosticsMapping`, `+TraceMapping`) |
| `Sources/OracleOS/WorldModel/Perception/AX/AXScanner.swift` | 1048L | ~180L | 7 (`+Observation`, `+Elements`, `+Screenshot`, `+Menu`, `+Browser`, `+Internal`) |
| `Sources/OracleController/ControllerStore.swift` | 1011L | 295L | 6 (`+System`, `+Recipes`, `+Operations`, `+Internal`; `+Copilot` pre-existing) |

---

## 5. Stale Milestone Docs (Root-level pollution)

9 stale milestone files at repo root:
`HANDOFF.md`, `PHASE_1_DONE.md`, `PHASE_1_FINALE.md`, `PHASE_1_STATUS.md`,  
`PHASE_3_DONE.md`, `PHASE_7_DONE.md`, `PHASE_8_DONE.md`, `TOTAL_REBUILD_DONE.md`,  
`COMPLETE_REBUILD_SUMMARY.md`

**Fix:** Archived under `docs/archive/`; `STATUS.md` remains the current state.

---

## 6. Persistence Namespace (Missing)

No `Sources/OracleOS/Persistence/` directory. Files that do file I/O live scattered across:

- `Sources/OracleOS/Learning/Recipes/RecipeStore.swift`
- `Sources/OracleOS/Learning/Project/ProjectMemoryStore.swift`
- `Sources/OracleOS/Learning/ExperienceStore.swift`
- `Sources/OracleOS/Runtime/RuntimeContainer.swift` (graph, WAL)

**Fix:** Create namespace README at `Sources/OracleOS/Persistence/README.md`,  
update `execution_boundary_guard.py` to scan for file I/O in non-persistence paths.

---

## 7. Vision Sidecar / Web Contract

- No typed endpoint contract between `VisionBridge.swift` and `vision-sidecar/server.py`
- No versioned API contract between `web/` frontend and the controller runtime
- Endpoint paths hardcoded in both sides without shared schema

**Fix:** ✅ Created `Sources/OracleOS/Contracts/VisionSidecarContract.swift` and  
`vision-sidecar/schema/endpoints.py` — typed request/response structs + canonical endpoint path constants for `/ground`, `/detect`, `/parse`, `/health`.

---

## 8. CI Guard Coverage

**Fix:** ✅ Guards strengthened and wired into CI:

- `scripts/mcp_boundary_guard.py` — now validates all 30 declared tools have dispatch entries; exits 1 on any gap
- `scripts/execution_boundary_guard.py` — retained and enforced
- `scripts/architecture_guard.py` — retained and enforced
- `.github/workflows/ci.yml` — `mcp_boundary_guard.py` runs before `swift build` on every push/PR

---

## Known Limitations of This Pass

- `oracle_workflow_execute` returns the workflow plan steps for LLM execution rather than running the planning stack directly (WorkflowExecutor requires full PlannerFamily context)
- File splits (Actions, AXScanner, RootView) preserve existing public API — no behavior change
- no changes to runtime spine: `RuntimeBootstrap → BootstrappedRuntime → RuntimeContainer → RuntimeOrchestrator → VerifiedExecutor → CommandRouter`
