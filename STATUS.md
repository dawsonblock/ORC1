# Oracle OS — Current Status

**Last updated:** 2026-04-02  
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
  → CommandRouter → TypedRouter
  → DefaultProcessAdapter   ← only Process() lives here
  → events emitted
  → CommitCoordinator.commit(events:)
  → reducers / projections applied
```

Protected live backbone: `VerifiedExecutor`, `CommitCoordinator`, `RuntimeBootstrap`, `DomainEvent`, `StateSnapshot`, `CriticLoop`, `PlanSimulator`, `ProgramKnowledgeGraph`, `WorldStateModel`, `ObservationChangeDetector`, `TaskLedger`, `TraceRecorder`, `RepairPipeline`, `BenchmarkBaseline`.

---

## Known Open Issues

1. **214 `[String: Any]` occurrences** across the codebase. Worst architectural leak: `ControllerRuntimeBridge+Mapping.swift` (18 hits — internal module boundary, should be typed mappers). See `AUDIT.md` for full classification.
2. **MCPDispatch.swift is 690 lines** mixing routing, timeout, result formatting, and all 28 tool implementations. Should be split into per-domain typed adapters.
3. **`VisionBridge.swift`** still uses dict transport beyond the perception entry point despite `VisionPerceptionContract.swift` existing.
4. **No CI wiring.** Guard scripts exist but no `.github/workflows/` file was found.
5. **ARCHITECTURE_RULES.md** had 5 ghost coordinator types and 2 ghost backbone modules (now corrected — see `AUDIT.md`).

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
