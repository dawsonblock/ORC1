# Oracle OS — Current Status

**Last updated:** 2026-04-02 (repair pass 5)  
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

1. **Remaining `[String: Any]` occurrences** across the codebase. Worst architectural leak: `ControllerRuntimeBridge+Mapping.swift` (internal module boundary — should be typed mappers). See `AUDIT.md` for full classification.
2. **MCPDispatch.swift is 690 lines** mixing routing, timeout, result formatting, and all 28 tool implementations. Should be split into per-domain typed adapters.
3. **No CI wiring.** Guard scripts exist but no `.github/workflows/` file was found.
4. **ARCHITECTURE_RULES.md** had 5 ghost coordinator types and 2 ghost backbone modules (now corrected — see `AUDIT.md`).

---

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
