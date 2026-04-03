# Oracle OS — Current Status

**Last updated:** 2025-07-16 (ORC1-main-5 — honesty pass)  
**Basis:** Source code audit. Claims below reflect what the code actually does.

---

## Live System State

| Property | Status |
|---|---|
| Swift target | macOS 14+ (arm64) |
| Source files | ~500 Swift files across 4 targets |
| Build | Must be verified in a valid Swift environment. See `scripts/verify-build.sh`. |

---

## Execution Boundary

**Clean.** Raw `Process()` is localized to exactly two files:
- `Sources/OracleOS/Execution/DefaultProcessAdapter.swift`
- `Sources/OracleOS/Execution/DefaultProcessAdapter+Daemon.swift`

`WorkspaceRunner` routes through the `ProcessAdapter` protocol. No CLI or controller target contains raw `Process()` calls.

---

## Runtime Spine (live)

```
RuntimeOrchestrator.submitIntent(_:)
  → MainPlanner / planner chain
  → VerifiedExecutor.execute(_:)
  → PolicyEngine.validate()
  → ApprovalStore.consumeApprovedReceipt()  [if token present — consumes single-use receipt]
  → ApprovalStore.createRequest()           [if requiresApproval and no token — blocks]
  → CommandRouter → TypedRouter
  → DefaultProcessAdapter   ← only Process() lives here
  → events emitted
  → CommitCoordinator.commit(events:)
  → reducers / projections applied
```

**Approval flow end-to-end:** The approval token is threaded from the MCP tool call (`approvalRequestID` param) → `executeThroughRuntime(approvalToken:)` → `RuntimeExecutionDriver` → intent metadata → `RuntimeOrchestrator` → `CommandMetadata.approvalToken` → `VerifiedExecutor`. Approval receipts are **action-fingerprint-bound**: `PolicyRules.commandFingerprint(_:)` computes a SHA256 of the serialised command payload; this fingerprint is stored in `ApprovalRequest` and checked by `ApprovalStore.consumeApprovedReceipt` — a different command submitted with the same token is rejected. Consumption is single-use (file deletion in `ApprovalStore`). Responses carry `approvalRequestID` and `approvalStatus` back to the caller.

**Experiment subsystem (separate path):** `oracle_experiment_search` is dispatched directly from `MCPDispatch` (async) to `ExperimentManager` → `ParallelRunner` → `WorktreeSandbox`. This path intentionally bypasses `RuntimeOrchestrator` and `VerifiedExecutor`. Isolation comes from isolated git worktrees. `WorktreeSandbox.apply()` enforces canonical path containment (same check pattern as `WorkspaceRunner.applyFile`) — absolute paths and `../` traversal are rejected before any write. The adapter is threaded from `WorkspaceRunner`.

Protected live backbone: `VerifiedExecutor`, `CommitCoordinator`, `RuntimeBootstrap`, `DomainEvent`, `StateSnapshot`, `CriticLoop`, `PlanSimulator`, `ProgramKnowledgeGraph`, `WorldStateModel`, `ObservationChangeDetector`, `TaskLedger`, `TraceRecorder`, `RepairPipeline`, `BenchmarkBaseline`.

---

## Known Open Issues

1. **Remaining `[String: Any]` occurrences** in some areas of the codebase. Key boundary `ControllerRuntimeBridge+Mapping.swift` now uses `ActionResultKey` and `CodeExecutionResultKey` typed constants throughout. The `code_execution` sub-dict is still `[String: Any]` structurally — a `ToolResult.data` architecture limitation, not a key-management issue. See `AUDIT.md` for full classification.
2. **`agentKind` / `plannerFamily` always nil in `ActionRunResult`:** `RuntimeExecutionDriver` only writes `TraceResultKey.cycleID` / `TraceResultKey.intentID` to the trace dict. `ControllerRuntimeBridge+Mapping` reads `traceData?["agent_kind"]` and `traceData?["planner_family"]`, which are never written. Both fields are always nil — known producer-consumer mismatch. Fix requires adding these fields to the intent response shape or the trace producer. No workaround exists.
3. **`MCPDispatch.swift` line count has been reduced** from earlier versions to ~359 lines. Routing, timeout, and tool dispatch remain in one file; splitting is not currently blocking.  
4. **CI is wired.** `.github/workflows/ci.yml` (build + swift test + mcp_boundary_guard) and `.github/workflows/architecture.yml` (architecture_guard.py) are present and run on every push and pull request.
5. **ARCHITECTURE_RULES.md** had 5 ghost coordinator types and 2 ghost backbone modules (now corrected — see `AUDIT.md`).

---

## ORC1-main-5 Honesty Pass — Changes Made

| Item | File(s) | Status |
|---|---|---|
| STATUS.md stale known issues (MCPDispatch line count, CI claim) | `STATUS.md` | Fixed |
| ARCHITECTURE.md overclaim that ALL CLI uses RuntimeBootstrap | `ARCHITECTURE.md` | Fixed — CLI diagnostic commands (Doctor, SetupWizard) intentionally bypass bootstrap |
| RuntimeContext doc comment contradicted its own contents | `Sources/OracleOS/Runtime/RuntimeContext.swift` | Fixed — doc accurately lists what is and isn't exposed, and what is forbidden |
| `CommandType.system` dead taxonomy | `Sources/OracleOS/Core/Command/Command.swift` | Removed — enum had 3 cases; `.system` was never emitted by any planner; `planSystemIntent` always produced `.ui` commands |
| `SystemRouter.swift` dead router | `Sources/OracleOS/Execution/Routing/SystemRouter.swift` | Replaced with tombstone comment explaining the removal |
| `CommandRouter.swift` dead `.system` branch | `Sources/OracleOS/Execution/Routing/CommandRouter.swift` | Removed — `systemRouter` property and `.system` case removed from init and execute |
| `fix_all.js`, `fixm.js` repair debris scripts | root | Removed — one-shot scripts from prior repair passes, already fully applied |

---



| Item | File(s) | Status |
|---|---|---|
| Raw string keys in `code_execution` bridge probes | `ActionResult.swift`, `ControllerRuntimeBridge+Mapping.swift` | Fixed — `CodeExecutionResultKey` enum added; 6 raw `codeData?["..."]` probes replaced with typed constants; 3 stale `?? traceData?[...]` fallbacks removed (trace never contained these keys) |
| Untyped `NSError` in sandbox containment | `WorktreeSandbox.swift` | Fixed — `SandboxError` typed enum added (`invalidRelativePath`, `containmentViolation`); `apply()` throws typed errors instead of `NSError` |
| No test coverage for sandbox containment | `Tests/OracleOSTests/Experiments/WorktreeSandboxContainmentTests.swift` | Fixed — new test file: absolute path rejection, traversal rejection, valid path write, typed error case assertions |
| `ExperimentManager.persistResults` undocumented bypass | `ExperimentManager.swift` | Fixed — doc comment added explaining it is internal experiment metadata, not a workspace mutation; inline comment on `createDirectory` confirms intent |
| VisionBridge fallback is silent | `VisionBridge.swift` | Fixed — `DefaultProcessAdapter()` fallback now logs `Log.warn("[VisionBridge] Using local DefaultProcessAdapter...")` so fallback is visible in runtime logs |
| CLI targets lack authority context | `Sources/oracle/Doctor.swift`, `Sources/oracle/SetupWizard.swift` | Fixed — EXECUTION AUTHORITY NOTE comment added to both; clarifies intentional separation from bootstrapped runtime |
| Docs overclaim execution spine universality | `README.md` | Fixed — "Every effect flows" narrowed to "Every **main-path** effect flows"; experiment subsystem bypass explicitly noted |
| REPAIR_SUMMARY.md no archived header | `REPAIR_SUMMARY.md` | Fixed — `[ARCHIVED]` header prepended; passes 1–3 covered here, passes 4–6 in STATUS.md |
| HANDOFF.md stale CLI routing claim | `HANDOFF.md` | Fixed — correcting note added to Phase 1-10% section; CLI tools are intentionally NOT routed through RuntimeOrchestrator |

## Repair Pass 6 — Closed Holes

| Item | File(s) | Status |
|---|---|---|
| Duplicate canonical containment logic | `WorkspaceRunner.swift`, `WorktreeSandbox.swift` | Fixed — `canonicalScopeRoot(_:)` extracted as module-internal helper; both call sites use it |
| Sandbox cleanup never called | `ParallelRunner.swift` | Fixed — `defer { sandbox.cleanup(using:) }` added; every experiment path now cleans its worktree |
| Raw string keys in recipe mapping | `ActionResult.swift`, `ControllerRuntimeBridge+Mapping.swift`, `RuntimeExecutionDriver.swift` | Fixed — `TraceResultKey` and `RecipeResultKey` enums added; all 14 raw string key uses replaced |
| VisionBridge mints its own process adapter | `VisionBridge.swift`, `RuntimeBootstrap.swift` | Fixed — `VisionBridge.configure(processAdapter:)` added; `RuntimeBootstrap` wires the shared adapter; fallback to `DefaultProcessAdapter()` preserved for out-of-runtime use |
| Doc overclaims on experiment path | `README.md`, `ARCHITECTURE.md` | Fixed — removed "replay the winner"; VerifiedExecutor universality narrowed; experiment bypass documented |
| Stale milestone files mislead readers | `COMPLETE_REBUILD_SUMMARY.md`, `TOTAL_REBUILD_DONE.md`, `PHASE_*_DONE.md`, `PHASES_1_2_DONE.md` | Archived — `[ARCHIVED]` header prepended; `STATUS.md` is the authoritative current state |

## Repair Pass 5 — Closed Holes

| Item | File(s) | Status |
|---|---|---|
| Approval not action-bound | `PolicyRules.swift`, `VerifiedExecutor.swift` | Fixed — `commandFingerprint(_:)` computes SHA256 of serialised payload; `ApprovalRequest.actionFingerprint` and `consumeApprovedReceipt` now use real fingerprint, not requestID |
| `FileMutationSpec.workspaceRoot` optional | `FileMutationSpec.swift`, `WorkspaceRunner.swift`, `CodeRouter.swift`, `MainPlanner+Planner.swift` | Fixed — property is now `String` (non-optional); planner guards nil path and falls back to `readFile` command rather than constructing an invalid spec |
| WorktreeSandbox no containment check | `WorktreeSandbox.swift` | Fixed — `apply()` rejects absolute paths and `../` traversal; performs canonical prefix check before any write |
| SystemRouter duplicate build/test/git | `SystemRouter.swift` | Fixed — `.build`, `.test`, `.git` payload cases return `failureOutcome` (planners always emit `.code` type; CodeRouter is sole owner) |
| CLI `runShell` via `BuildSpec` misuse | `Doctor.swift`, `SetupWizard.swift`, `main.swift` | Fixed — `runShell`/`runShellLive` now use `DefaultProcessAdapter.run(SystemCommand(...))` directly; `executor: VerifiedExecutor` dependency and unnecessary runtime bootstrap removed |
| Inline string keys in result mapping | `ActionResult.swift`, `RuntimeExecutionDriver.swift`, `ControllerRuntimeBridge+Mapping.swift` | Fixed — `ActionResultKey` enum provides typed constants; all three files use constants throughout |

## Repair Pass 4 — Closed Holes

| Item | File(s) | Status |
|---|---|---|
| Approval token threading (e2e) | `VerifiedExecutor`, `RuntimeOrchestrator`, `RuntimeExecutionDriver`, `Actions+*.swift`, `IntentResponse`, `CommandMetadata` | Fixed — token threaded from MCP call through to executor; consume/create paths wired; response carries approval fields |
| nil workspaceRoot in edit path | `MainPlanner+Planner.swift` | Fixed — resolves from intent metadata or repository snapshot |
| BuildSpec/TestSpec ignored fields | `BuildSpec.swift`, `TestSpec.swift`, `MainPlanner+Planner.swift` | Fixed — removed `scheme`, `destination`, `failureOnly`; spec types now match runner capabilities exactly |
| Experiment subsystem undocumented | `WorktreeSandbox.swift`, `ExperimentManager.swift` | Fixed — explicit header comment: NOT on main execution path |
| WorktreeSandbox own ProcessAdapter | `WorktreeSandbox.swift`, `ParallelRunner.swift`, `WorkspaceRunner.swift` | Fixed — adapter threaded from `WorkspaceRunner` through `ParallelRunner` to sandbox; no local `DefaultProcessAdapter()` construction |
| VisionBridge untyped HTTP bodies | `VisionBridge.swift`, `VisionSidecarContract.swift`, `VisionScanner.swift`, callers | Fixed — `httpPostTyped`/`httpGetTyped` use JSONEncoder/JSONDecoder; all public methods use typed contract structs; `healthCheck()` returns `VisionHealthResponse?` |

## Repair Pass 3 — Closed Holes

| Item | File(s) | Status |
|---|---|---|
| `applyFile()` workspace containment | `WorkspaceRunner.swift` | Fixed — enforces containment; rejects nil workspaceRoot and path traversal |
| `WorkspaceScope.resolve()` prefix bug | `WorkspaceScope.swift` | Fixed — uses trailing-slash prefix; handles absolute paths |
| Duplicate `.file` handler | `SystemRouter.swift` | Fixed — `.file` payload returns failure from SystemRouter; CodeRouter is sole owner |
| Approval gate not wired | `VerifiedExecutor.swift`, `RuntimeBootstrap.swift` | Fixed — `requiresApproval` now routes to `ApprovalStore.createRequest()` |
| Invalid build/test flags | `WorkspaceRunner.swift` | Fixed — uses `--configuration` / `--filter` (SwiftPM flags); dropped Xcode-only `-scheme`, `-destination`, `-failureOnly` |
| VisionBridge inline path strings | `VisionBridge.swift` | Fixed — paths use `VisionSidecarEndpoint.*` constants |

---

## What Is Experimental / Optional

- `vision-sidecar/` — Python vision sidecar. Not required for core operation.
- `web/` — Small frontend. Not part of the Swift build.
- Both should be excluded from release build surface.

---

## Authoritative References

| Topic | File |
|---|---|
| Architecture invariants | `ARCHITECTURE_RULES.md` |
| Audit findings | `AUDIT.md` |
| Product contract | `docs/PRODUCT_CONTRACT.md` |
| Release checklist | `docs/RELEASE_CHECKLIST.md` |
| Baseline point-in-time | `BASELINE.md` |

> Historical milestone docs (`PHASE_*_DONE.md`, `HANDOFF.md`, `TOTAL_REBUILD_DONE.md`, `COMPLETE_REBUILD_SUMMARY.md`) are archived and marked as such. Do not treat them as current state.
