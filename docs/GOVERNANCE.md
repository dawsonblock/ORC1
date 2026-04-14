# Oracle-OS Governance

This document establishes the development rules and architectural invariants for Oracle-OS.

## Document Authority Levels

### Authoritative Documents

These documents describe the runtime as it actually works and MUST be kept current:

| Document | Purpose |
| --- | --- |
| [../ARCHITECTURE.md](../ARCHITECTURE.md) | System overview, component relationships |
| [../ARCHITECTURE_RULES.md](../ARCHITECTURE_RULES.md) | Invariants, anti-patterns, enforcement |
| [runtime_invariants.md](runtime_invariants.md) | Core runtime laws that cannot be broken |
| [architecture/runtime_spine.md](architecture/runtime_spine.md) | Execution flow, commit protocol |

### Archival Documents

These documents were accurate at specific points in development but may not reflect current state:

| Document | Purpose | Baseline Date |
| --- | --- | --- |
| [runtime_baseline_36.md](runtime_baseline_36.md) | Historical baseline | Pre-consolidation |
| [runtime_baseline_38.md](runtime_baseline_38.md) | Historical baseline | Pre-consolidation |

## Architectural Invariants

The following rules are enforced by guard scripts and governance tests.
`scripts/architecture_guard.py` owns the broad runtime freeze, while focused
guards and tests pin seam-level hardening that a tree scan alone cannot prove.

### 1. Single Commit Authority

- Only `CommitCoordinator` may append events to the event store
- Only `CommitCoordinator` may mutate `WorldStateModel` via reducers
- Bypassing this path breaks replay determinism

### 2. Event Normalization

- All runtime event producers MUST use `DomainEventFactory`
- Events MUST include `commandKind`, `status`, and `notes` fields
- Raw `EventEnvelope` construction outside the factory is forbidden

### 3. Execution Boundary

- `VerifiedExecutor` is the only layer that may produce main-path gated desktop side effects
- `VerifiedExecutor` MUST check preconditions before execution
- `VerifiedExecutor` MUST NOT commit state — only emit events
- Service persistence remains in its own bounded subsystems (`CommitCoordinator`, event storage, memory, workflow, diagnostics, and other write authorities enforced by `scripts/execution_boundary_guard.py`)

### 4. State Immutability

- `WorldModelSnapshot` is a value type — callers cannot mutate runtime state
- Direct access to `WorldStateModel` is forbidden outside runtime assembly

### 5. WAL Protocol

- `CommitWAL.writePending()` MUST be called before `EventStore.append()`
- `CommitWAL.clear()` MUST be called after successful append
- `CommitCoordinator.recoverIfNeeded()` MUST be called at startup

## Enforcement

### Pre-Commit Checks

```bash
# Run architecture guard
python3 scripts/architecture_guard.py

# Run focused boundary guards
python3 scripts/execution_boundary_guard.py
python3 scripts/mcp_boundary_guard.py
python3 scripts/cli_contract_guard.py

# Run all tests
swift test

# Build oracle product
swift build --product oracle

# Canonical local proof
bash scripts/verify-build.sh
```

### Hardening Proof Coverage

`Tests/OracleOSTests/Governance/HardeningProofTests.swift` is part of the live
governance contract. It proves that:

- MCP category handlers keep typed payloads after request decode and export
  through the shared legacy seam rather than ad hoc nested dictionaries
- the typed MCP boundary requires an explicit request version at the outer
  adapter seam instead of defaulting omitted versions inside category handlers
- the MCP tool catalog remains defined by typed schema models in
  `Sources/OracleOS/MCP/MCPTools.swift`
- experiment diagnostics recover persisted search results from repository
  snapshot or sandbox-derived workspace roots and leave experiment metadata
  unavailable when persisted evidence cannot be recovered
- recipe, workflow, and project-memory persistence remain explicit
  service-owned write surfaces guarded by `scripts/execution_boundary_guard.py`
  instead of becoming hidden commit-authority paths
- `ControllerRuntimeBridge` consumes typed `ToolResult` views for authoritative
  action and code-execution truth
- CLI-only exception paths (`oracle setup`, `oracle doctor`) still reuse shared
  typed seams for Claude Desktop config and vision bridge status

### CI Requirements

All PRs must pass:

1. `.github/workflows/ci.yml` runs `bash scripts/verify-build.sh` on macOS and publishes `local/verify/latest/` as the canonical shared proof artifact
2. `.github/workflows/architecture.yml` passes as the focused supplemental guard job
3. `.github/workflows/controller-release.yml` is packaging validation only and is not a substitute for the canonical verifier
4. Historical logs, ad hoc terminal output, and archived milestone notes are never treated as current certification

## Evolution Process

To modify architectural invariants:

1. Open an issue describing the proposed change
2. Document the change in `ProjectMemory/architecture-decisions/`
3. Update `ARCHITECTURE_RULES.md` with new rules
4. Update affected authoritative documents
5. Update `scripts/architecture_guard.py` if enforcement changes
6. Get review from a maintainer
