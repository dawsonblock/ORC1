# OracleOS Product Contract

This file states the live product surface in this checkout. Historical rebuild, handoff, and phase docs live under [archive/](archive/) and are not current certification.

## Product Scope

OracleOS is a Swift-native macOS automation runtime with three live surfaces:

1. **MCP** — Model Context Protocol tool server
2. **Controller** — native macOS GUI for human-in-the-loop monitoring and approval
3. **CLI** — `oracle` binary for local setup, diagnostics, and recipe execution

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

### 2. Desktop actions are approval-gated when policy requires it

Risky actions such as click, type, press, hotkey, scroll, focus, window operations, and recipe steps marked `requiresApproval` pass through `PolicyEngine` and may be gated by `ApprovalStore`.

When a gated action pauses, the caller receives an `approval_request_id`. Resuming the action requires that token.

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
| **Read-only** | Observation and perception | AX inspection, screenshots, sidecar-backed perception |

`VerifiedExecutor` governs gated desktop actions. Service persistence remains in its own subsystems.

### 5. Evidence must come from current local verification

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
