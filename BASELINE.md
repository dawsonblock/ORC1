# Oracle-OS Baseline — March 31, 2026

This file records the baseline description captured at the start of the Phase 6 consolidation.
Source-structure facts below are derived from code inspection. Numeric build/test
status is NOT certified by the archived diagnostics logs in this repo and must be
re-generated in a supported Swift environment.

## Toolchain

| Property | Value |
|---|---|
| Swift | 6.3 (swiftlang-6.3.0.123.5) |
| Xcode | 26.4 (Build 17E192) |
| macOS Target | 26.2 (arm64-apple-macosx26.0) |

## Verification Path

```
bash scripts/verify-build.sh
```

The verifier runs the boundary guards, `swift build -c release`, and `swift test`, then writes current evidence to `local/verify/latest/`. `.github/workflows/ci.yml` runs the same verifier and is the canonical shared proof surface.

> **Note:** The archived Diagnostics logs (`runtime_baseline_36_build.log`,
> `runtime_baseline_36_test.log`) contain only `bash: line 1: swift: command not found`
> and are NOT valid proof artifacts. Use `scripts/verify-build.sh` or run the commands
> above in a supported Swift environment to regenerate current evidence. No checked-in
> packaged-controller artifact in this repo should be treated as current UI health proof.

## Canonical Entry Points

| Surface | Entry |
|---|---|
| MCP server | `Sources/OracleOS/MCP/MCPServer.swift` → `MCPDispatch.handle(_:)` |
| Controller app | Supported operator UI in `Sources/OracleController/` via `OracleController.xcodeproj` |
| Controller host | Bundled helper adapter in `Sources/OracleControllerHost/ControllerRuntimeBridge.swift` |
| CLI / oracle tool | `Sources/oracle/` |

## Canonical Runtime Path

```
RuntimeBootstrap.makeBootstrappedRuntime()
  → RuntimeOrchestrator.submitIntent(_:)
  → MainPlanner.plan(intent:state:)
  → VerifiedExecutor.execute(_:)
  → CommandRouter → UIRouter / CodeRouter
  → events emitted
  → CommitCoordinator.commit(_:)
  → reducers / projections applied
```

## Known Issues at Baseline

- `RuntimeContext` is not instantiated by any live Sources/ code path as of 2026-04-03. It is kept as a guard structure (compile-time `@available(*, unavailable)` blocks on execution-adjacent properties) because enforcement tests scan it. *(Not scheduled for deletion — role is boundary enforcement, not execution authority.)*
- `RuntimeExecutionDriver` is a translational bridge (ActionIntent → Intent → RuntimeOrchestrator). Retained, not removed; correctly scoped. *(Resolved — no direct executor access.)*
- `MCPDispatch` held both `_bootstrappedRuntime` and `_runtimeContext`. Dual-path risk. *(Resolved — `_runtimeContext` no longer present in MCPDispatch.)*
- `[String: Any]` dictionaries cross task-group and actor boundaries in MCPDispatch. *(Partially resolved — typed `MCPToolRequest`/`MCPToolResponse` via `MCPBoundary.swift`. Legacy `handle(_ params: [String: Any])` entry point retained for MCPServer compatibility. 214 occurrences remain, mostly at external perception/API boundaries. See `AUDIT.md`.)*
- Root contained 46 legacy repair scripts, logs, and one-off test files (now quarantined in `tools/quarantine/`).
- `vision-sidecar` is an optional external service edge and `web` is demo scaffolding. Neither is the supported operator UI. *(Unchanged.)*

## Phase 6 Goals — Resolution Status (2026-04-03)

1. ~~Delete `RuntimeContext`~~ **Reclassified:** Not instantiated in any live code path; kept as guard structure with enforcement tests. See Objective 3 resolution.
2. ~~Remove `RuntimeExecutionDriver`~~ **Not done:** `RuntimeExecutionDriver` is retained as a correctly scoped translational bridge (ActionIntent → Intent → RuntimeOrchestrator). It does not access VerifiedExecutor directly. Removal would require changing the controller bridge surface.
3. ~~Retype MCP boundary~~ **Partially done:** `MCPBoundary.swift` typed `MCPToolRequest`/`MCPToolResponse` added. Legacy `handle(_ params: [String: Any])` entry point retained for MCPServer stdin compatibility. External boundary; remaining dict usage is at the stdin edge only.
4. ~~Define `v1` contracts for vision-sidecar and web~~ **Not done (web demoted):** web is explicitly labeled mock/demo-only as of ORC1-main-6. Vision-sidecar retains `VisionPerceptionContract` / `VisionSidecarContract` typed models.
5. ~~Add semantic governance tests~~ **Done:** Behavioral tests added in `ExecutionBoundaryEnforcementTests.swift` (`testRuntimeBootstrapIsDeterministic`, `testCommitCoordinatorAppliesReducersBeforeVisibility`, `testVerifiedExecutorIsOnlyExecutionPath`). Source-scan tests retained where static enforcement is the right tool.
6. ~~Isolate experimental modules~~ **Not done:** `vision-sidecar` and `web` remain in the repo but are not Swift build targets. No Package.swift inclusion.
7. ~~Rewrite docs to reflect exactly what is supported~~ **Substantially done:** ORC1-main-5 through ORC1-main-7 passes corrected STATUS.md, ARCHITECTURE.md, ARCHITECTURE_RULES.md, AUDIT.md, and BASELINE.md.
