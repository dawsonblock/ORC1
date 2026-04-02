# Baseline Repair Pass — Oracle OS

**Date:** 2025-08  
**Status:** In Progress  
**Scope:** Bounded 11-step pass to fix contract drift, monolith surfaces, and guard coverage.

---

## 1. MCP Contract Gap (Critical)

30 tools are declared in `MCPTools.swift`. Before this pass only **8 were dispatched**;
the remaining 22 returned `"Unknown tool"` at runtime.

### Tools grouped by category

| # | Tool | Category | Was Handled? |
|---|------|----------|--------------|
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
|-----------|-----------|
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

## 3. mcp_boundary_guard.py (Trivial check)

Current implementation (`scripts/mcp_boundary_guard.py`, 12 lines):
- Only verifies that 2 function names (`handle` and `dispatch`) exist in MCPDispatch.swift
- Does NOT compare defined tools vs dispatched tools
- Does NOT detect new tools added to MCPTools.swift but missing from dispatch

**Fix:** Rewrite to parse MCPTools.swift for tool names and compare against MCPDispatch.swift switch cases.  
**Add:** `Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift` — Swift unit test asserting 100% coverage.

---

## 4. File Size Monoliths (Pre-pass measurements)

| File | Lines | Split target |
|------|-------|-------------|
| `Sources/OracleController/RootView.swift` | 2228 | Composable views |
| `Sources/OracleOS/Intent/Actions/Actions.swift` | 1226 | 6 action files |
| `Sources/OracleControllerHost/ControllerRuntimeBridge.swift` | 929 | Extension split |
| `Sources/OracleOS/WorldModel/Perception/AX/AXScanner.swift` | 1048 | 8 scanner files |
| `Sources/OracleController/ControllerStore.swift` | 1011 | Domain slices |

---

## 5. Stale Milestone Docs (Root-level pollution)

9 stale milestone files at repo root:
`HANDOFF.md`, `PHASE_1_DONE.md`, `PHASE_1_FINALE.md`, `PHASE_1_STATUS.md`,  
`PHASE_3_DONE.md`, `PHASE_7_DONE.md`, `PHASE_8_DONE.md`, `TOTAL_REBUILD_DONE.md`,  
`COMPLETE_REBUILD_SUMMARY.md`

**Fix:** Add archival banner to each; move to `docs/archive/` eventually.

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

## 7. Vision Sidecar / Web Contract (Implicit)

- No typed endpoint contract between `VisionBridge.swift` and `vision-sidecar/server.py`
- No versioned API contract between `web/` frontend and the controller runtime
- Endpoint paths hardcoded in both sides without shared schema

**Fix:** Create `Sources/OracleOS/Contracts/VisionSidecarContract.swift` and  
`vision-sidecar/schema/endpoints.py` with matching endpoint definitions.

---

## 8. CI Guard Coverage

Current guard scripts:
- `scripts/mcp_boundary_guard.py` — trivial (see §3)
- `scripts/execution_boundary_guard.py` — checks `Process()` calls, narrow scope
- `scripts/architecture_guard.py` — only checks 2 files (`AgentLoop.swift`, `Planner.swift`)

**Fix:** Strengthen all three guards. Add MCP coverage test in Swift.

---

## Known Limitations of This Pass

- `oracle_workflow_execute` returns the workflow plan steps for LLM execution rather than running the planning stack directly (WorkflowExecutor requires full PlannerFamily context)
- `oracle_memory_draft` with `kind=risk` calls `projectStore.writeRiskDraft()` directly since UnifiedMemoryStore has no `recordRisk` wrapper
- File splits (Actions, AXScanner, RootView) preserve existing public API — no behavior change
- no changes to runtime spine: `RuntimeBootstrap → BootstrappedRuntime → RuntimeContainer → RuntimeOrchestrator → VerifiedExecutor → CommandRouter`
