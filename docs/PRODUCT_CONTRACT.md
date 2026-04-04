# OracleOS Product Contract

This file states the live product surface in this checkout. Historical rebuild, handoff, and phase docs live under [archive/](archive/) and are not current certification.

## Product Scope

OracleOS is a Swift-native macOS automation runtime with three live entry points and one supported human operator UI:

1. **Controller** — supported native macOS operator UI for monitoring, approvals, recipes, diagnostics, and project memory
2. **MCP** — Model Context Protocol tool server for programmatic use
3. **CLI** — `oracle` binary for local setup, diagnostics, and recipe execution

`OracleControllerHost` is the bundled helper adapter for the desktop UI. It boots one `OracleOS` runtime per app launch and forwards typed requests into that runtime. It is not a second planner, executor, or commit authority.

`MCPDispatch` is the public MCP tool entrypoint. `MCPRuntimeHost` owns reusable runtime bootstrap, reuse, and reset semantics for the MCP host process behind that entrypoint.

`OracleControllerShared` is intentionally split across `ControllerModels.swift`, `ControllerDiagnosticsModels.swift`, and `ControllerTraceModels.swift` so the shared desktop contract mirrors action/control, diagnostics/host state, and trace/recipe/dashboard ownership boundaries.

OracleOS is not a cloud service, not a browser product, and not a general-purpose agent framework. It is intentionally scoped to local macOS automation with explicit approval and execution boundaries.

## Live Guarantees

### 1. The MCP surface is bounded and implemented

OracleOS currently exposes 30 tools across 9 categories. Tool names are declared in `Sources/OracleOS/MCP/MCPTools.swift` and dispatched in `Sources/OracleOS/MCP/MCPDispatch.swift`.

The guard script `scripts/mcp_boundary_guard.py` and `Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift` enforce declared-tool coverage.

| Category | Count |
|---|---:|
| Perception | 7 |
| Actions | 7 |
| Wait | 1 |
| Recipes | 5 |
| Vision | 2 |
| Memory | 2 |
| Experiments | 1 |
| Architecture | 2 |
| Workflows | 3 |

See [../ORACLE-MCP.md](../ORACLE-MCP.md) for the user-facing tool catalog.

### 2. Desktop actions that enter the runtime are approval-gated when policy requires it

Risky actions such as click, type, press, hotkey, scroll, focus, window operations, and recipe steps marked `requiresApproval` pass through `PolicyEngine` and may be gated by `ApprovalStore`.

When a gated action pauses, the caller receives an `approval_request_id`. Resuming the action requires that token.

The controller's Wait action is not a side-effecting runtime action. It is an observational condition check handled by the host and therefore does not enter `VerifiedExecutor`.

### 3. The main runtime spine is stable for main-path effects

The current main-path runtime spine is:

```text
RuntimeBootstrap
    -> RuntimeOrchestrator
    -> MainPlanner
    -> VerifiedExecutor
    -> CommandRouter
    -> UIRouter / CodeRouter
    -> CommitCoordinator
```

Surface code is a consumer of this spine, not a mutator of it.

Explicit exceptions:

- `oracle_experiment_search` dispatches to the experiment subsystem by design and does not go through `RuntimeOrchestrator` or `VerifiedExecutor`
- `Sources/oracle/Doctor.swift` and `Sources/oracle/SetupWizard.swift` are tooling-only shell exceptions
- `vision-sidecar/` is an optional service edge, not part of committed-state authority

### 4. Side effects follow a three-tier taxonomy

| Tier | Scope | Examples |
|---|---|---|
| **Gated** | User-approved desktop actions | click, type, hotkey through `VerifiedExecutor` |
| **Service** | Infrastructure persistence | traces, memory, graph, recipes, workflows, telemetry |
| **Read-only** | Observation and perception | AX inspection, screenshots, controller Wait checks, sidecar-backed perception |

`VerifiedExecutor` governs gated desktop actions. Service persistence remains in its own subsystems.

### 5. The live controller/runtime result seam is typed internally

The live controller/runtime result seam is typed internally. `ToolResult` exposes `actionResult`, `traceResult`, `codeExecutionResult`, and `recipeRunResult`, and the controller host mapping layer consumes those typed views directly. Legacy nested dictionaries remain only as compatibility export at the outer result seam.

### 6. Evidence must come from current local verification

Current evidence comes from local `swift build`, `swift test`, and [../scripts/verify-build.sh](../scripts/verify-build.sh) in a valid environment.

Archived repair notes, milestone docs, and checked-in diagnostics are historical only. The current tree should not be described as a zero-warning build unless it has been re-verified as such.

## What OracleOS Does Not Guarantee

- Vision grounding accuracy
- Experiment search determinism
- Workflow synthesis coverage from sparse trace history
- Sub-second automation latency on all macOS applications

## References

- [../README.md](../README.md) — repo overview and quick start
- [../STATUS.md](../STATUS.md) — current repo state and known limits
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — runtime model and execution spine
- [../BASELINE.md](../BASELINE.md) — evidence posture and baseline notes
- [../AUDIT.md](../AUDIT.md) — forensic cleanup findings
- [../ORACLE-MCP.md](../ORACLE-MCP.md) — full MCP tool reference
- [architecture/runtime_spine.md](architecture/runtime_spine.md) — runtime spine reference
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) — live release gate checklist
- [BASELINE_REPAIR_PASS.md](BASELINE_REPAIR_PASS.md) — historical repair-pass record
- [../ProjectMemory/README.md](../ProjectMemory/README.md) — project memory conventions
