# Repo Audit — Oracle OS

**Date:** 2026-04-02  
**Scope:** Truth audit and boundary review per repair-bot sequence.  
**Method:** Source code is the ground truth. Docs that contradict code are wrong.

---

## 1. Stale / Misleading Docs

| File | Problem |
|------|---------|
| `STATUS.md` | Says "REMAINING: Phase 1 Finale — 4 Process() violations in CLI/UI files". Those violations no longer exist in source. File describes past work as open. |
| `ARCHITECTURE_RULES.md` | Coordinator Ownership table lists 5 coordinators (ExecutionCoordinator, RecoveryCoordinator, DecisionCoordinator, LearningCoordinator, StateCoordinator) that do not exist in source. Also lists `TaskGraph` and `TraceStore` as protected backbone — neither type exists under those names. Also cites `CoordinatorBoundaryTests` in enforcement suite — file does not exist. |
| `REBUILD_PLAN.md` | Describes in-progress phases. Rebuild is complete. File is a process artifact. |
| `INDEX.md` | "Rebuild Documentation Index" for a completed rebuild. Stale entry point. |
| `BASELINE.md` | Known Issues section lists `_runtimeContext` dual-path in MCPDispatch. That dual-path is gone. Also lists `RuntimeExecutionDriver` as "transitional bridge slated for removal" — it was retained and scoped correctly, not removed. On balance BASELINE.md is a useful point-in-time record; mark known-issues as resolved. |
| `PHASE_1_DONE.md`, `PHASE_1_FINALE.md`, `PHASE_1_STATUS.md`, `PHASE_3_DONE.md`, `PHASE_7_DONE.md`, `PHASE_8_DONE.md`, `PHASES_1_2_DONE.md`, `TOTAL_REBUILD_DONE.md`, `COMPLETE_REBUILD_SUMMARY.md`, `HANDOFF.md` | All already marked `[ARCHIVED]`. No further action required. |

---

## 2. Ghost / Missing Architecture Items (ARCHITECTURE_RULES.md)

These types are named in ARCHITECTURE_RULES.md as live governing items but do not exist in `Sources/`:

| Named in doc | Actual status |
|---|---|
| `ExecutionCoordinator` | Does not exist. No file, no type, no reference in source. |
| `RecoveryCoordinator` | Does not exist. Recovery logic lives in `Sources/OracleOS/Recovery/` (strategies + coordinator-less). |
| `DecisionCoordinator` | Does not exist. Planning path goes directly through `MainPlanner` / `RuntimeOrchestrator`. |
| `LearningCoordinator` | Does not exist. Learning is handled by `RecipeEngine`, `TraceRecorder`, `UnifiedMemoryStore`. |
| `StateCoordinator` | Does not exist. State is managed through `CommitCoordinator` + reducers. |
| `TaskGraph` | Does not exist under that name. Actual live type: `TaskLedger` (in `Sources/OracleOS/TaskLedger/`). |
| `TraceStore` | Does not exist under that name. Actual: `TraceRecorder`, `MemoryEventStore`, observability structs in `Sources/OracleOS/Observability/`. |
| `CoordinatorBoundaryTests` | Listed in enforcement suite — file does not exist in `Tests/OracleOSTests/Governance/`. |

**Backbone modules that DO exist:**

| Module | File |
|---|---|
| `VerifiedExecutor` | `Sources/OracleOS/Execution/VerifiedExecutor.swift` |
| `CommitCoordinator` | `Sources/OracleOS/Events/CommitCoordinator.swift` |
| `RuntimeBootstrap` | `Sources/OracleOS/Runtime/RuntimeBootstrap.swift` |
| `DomainEvent` | `Sources/OracleOS/Events/DomainEvent.swift` |
| `StateSnapshot` | `Sources/OracleOS/State/StateSnapshot.swift` |
| `CriticLoop` | `Sources/OracleOS/Execution/Critic/CriticLoop.swift` |
| `PlanSimulator` | `Sources/OracleOS/Planning/Reasoning/PlanSimulator.swift` |
| `ProgramKnowledgeGraph` | `Sources/OracleOS/Code/Intelligence/ProgramKnowledgeGraph.swift` |
| `WorldStateModel` | `Sources/OracleOS/WorldModel/WorldStateModel.swift` |
| `ObservationChangeDetector` | `Sources/OracleOS/WorldModel/ObservationChangeDetector.swift` |
| `RepairPipeline` | `Sources/OracleOS/Code/Repair/RepairPipeline.swift` |
| `BenchmarkBaseline` | `Sources/OracleOS/Common/Diagnostics/BenchmarkBaseline.swift` |
| `RuntimeOrchestrator` | `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` (actor) |

---

## 3. Execution Boundary — Raw Process() Violations

**Result: CLEAN.**

`Process()` is correctly localized to exactly two files:
- `Sources/OracleOS/Execution/DefaultProcessAdapter.swift`
- `Sources/OracleOS/Execution/DefaultProcessAdapter+Daemon.swift`

`WorkspaceRunner.swift` routes through `processAdapter.run()` (adapter interface). No CLI or controller files contain raw `Process()`.  
No `NSTask`, `popen`, or `system()` calls found outside adapters.  
STATUS.md's claim of 4 open violations is stale — already resolved.

---

## 4. Dynamic Payload Sites — Risk Classification

214 occurrences of `[String: Any]` across the codebase.

### Category 1 — Acceptable edge bridges (external API)

| File | Count | Reason |
|------|-------|--------|
| `Sources/OracleOS/Browser/Perception/DOMScanner.swift` | 16 | Browser JS bridge — JSON deserialized from AppleScript/CDP response. External protocol boundary. |
| `Sources/OracleOS/WorldModel/Perception/AX/AXScanner+Context.swift` | 7 | AX API returns untyped dicts; parsing at perception boundary is acceptable. |
| `Sources/OracleOS/WorldModel/Perception/AX/AXScanner+Shared.swift` | 4 | Same — AX framework boundary. |
| `Sources/OracleOS/WorldModel/Perception/Vision/ScreenCapture.swift` | 4 | Vision sidecar JSON response parsing. |
| `Sources/OracleOS/Planning/Reasoning/OpenAIProvider.swift` | 6 | LLM API HTTP response — external boundary. |
| `Sources/oracle/SetupWizard.swift` | 7 | CLI user-facing; diagnostic output. |
| `Sources/oracle/Doctor.swift` | 3 | CLI diagnostic output. |
| `Sources/OracleOS/Common/Types.swift` | 6 | Shared utility types. |

### Category 2 — Temporary compatibility shims (need typed models)

| File | Count | Problem |
|------|-------|---------|
| `Sources/OracleOS/MCP/MCPDispatch.swift` | 17 | Legacy `handle(_ params: [String: Any])` entry point retained for MCPServer compatibility. Internal result-building dicts are JSON-serialization intermediaries (acceptable). The legacy entry point is the shim. |
| `Sources/OracleOS/MCP/MCPTools.swift` | 15 | Tool schema declarations use `[String: Any]` for JSON schema representation. |
| `Sources/OracleOS/MCP/MCPServer.swift` | 13 | Receives raw stdin JSON; parses to `[String: Any]` before forwarding to MCPDispatch. Edge boundary. |
| `Sources/OracleOS/MCP/MCPBoundary.swift` | 13 | `JSONValue` model already present; `[String: Any]` usage is in legacy bridge methods. |
| `Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift` | 5 | Translation bridge; some dict usage in intermediate mapping. |
| `Sources/OracleOS/TaskLedger/TaskLedgerStore.swift` | 5 | Persistence serialization. |

### Category 3 — Architectural leaks (internal transport across module boundaries)

**Result after thorough analysis: NONE.** Every site classified as Category 3 in the initial pass resolved to Category 1 or Category 2 on closer inspection:

| File | Initial concern | Corrected classification |
|------|-----------------|--------------------------|
| `Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift` | Cross-module dict transport | **Category 2.** `mapActionResult` accesses inherently-dynamic `ToolResult.data`; `recipeDictionary` is a JSON serialization shim for snake_case→camelCase CodingKey mismatch; `loadClaudeConfig` is external JSON. |
| `Sources/OracleOS/WorldModel/Perception/Vision/VisionBridge.swift` | Dict return type beyond perception boundary | **Category 1.** `detect()` and `parse()` return raw HTTP JSON from the Python sidecar. The result is relayed as-is to the MCP caller via `ToolResult.data`. The whole pipeline is external-to-external relay — `VisionPerceptionContract` typed models are used by the world-model reconciliation path, not the relay path. |
| `Sources/OracleOS/Intent/Actions/Actions.swift` | Action payload dicts | **Category 2.** The 4 hits are `private extractString/Int/Double/Bool(_ params: [String: Any], ...)` helpers at the MCPDispatch edge. Params originate from MCPServer stdin parsing. |
| `Sources/OracleOS/WorldModel/StateAbstractionEngine.swift` | Dict intermediaries | **Category 2.** All 4 hits are inside `toDict()` serialization helpers — dicts are built and immediately serialized via `JSONSerialization`; they are never stored or passed between functions. |
| `Sources/OracleOS/Common/Diagnostics/DiagnosticsWriter.swift` | Internal dict transport | **Category 2.** All 11 hits are in `toDict()` serialization helpers or `JSONSerialization.data(withJSONObject:)` calls for writing JSON files. The `PathSnapshot.scoreBreakdowns: [[String: Any]]` field is diagnostics-only and assembled at the diag write site. |

---

## 5. Overloaded Translation Files

| File | Lines | Problem |
|------|-------|---------|
| `Sources/OracleOS/MCP/MCPDispatch.swift` | 690 | Mixes routing, timeout management, result formatting, and all 28 tool implementations in one file. **Phase 5 target**: extract per-domain handlers to `MCPDispatch+Recipes.swift`, `MCPDispatch+Memory.swift`, `MCPDispatch+Architecture.swift`, `MCPDispatch+Workflow.swift`. |
| `Sources/OracleControllerHost/ControllerRuntimeBridge+Mapping.swift` | 343 | Mixed mapping concerns. Reclassified Category 2 — recipeDictionary is a serialization shim, ToolResult.data access is inherently dynamic. |
| `Sources/OracleOS/MCP/MCPTools.swift` | 399 | Tool schema declarations — large but single-purpose; acceptable. |

---

## 6. Diagnostics / Proof Gaps

- `Diagnostics/` folder contains logs showing `swift: command not found`. These are not valid build evidence.
- `BASELINE.md` claims `swift build -c release → Build complete` and 638 tests passing — but no reproducible script to regenerate this evidence exists.
- No CI configuration file (`.github/workflows/`) was found. CI enforcement of guard scripts is documented but not wired.
- Governance tests exist and appear real. They primarily use source-file text scanning, not type-import checks.

---

## Recommended Action Order

1. **DONE (this file):** Produce audit.
2. **Reconcile ARCHITECTURE_RULES.md:** Remove ghost coordinators and `CoordinatorBoundaryTests`. Rename `TaskGraph` → `TaskLedger`, `TraceStore` → live equivalent. No new abstractions.
3. **Rewrite STATUS.md:** Remove open-issue claims that are resolved. State only current reality.
4. **Category 3 leaks:** Eliminate `[String:Any]` in `ControllerRuntimeBridge+Mapping.swift`, `VisionBridge.swift`, `DiagnosticsWriter.swift`.
5. **MCPDispatch refactor:** Extract per-domain result builders into typed adapters; keep dispatch() as route-only.
6. **Proof path:** Add `scripts/verify-build.sh` that runs `swift build` and `swift test` and records output.
