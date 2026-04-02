# Oracle-OS Governance

This document establishes the development rules and architectural invariants for Oracle-OS.

## Document Authority Levels

### Authoritative Documents

These documents describe the runtime as it actually works and MUST be kept current:

| Document | Purpose |
|----------|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System overview, component relationships |
| [ARCHITECTURE_RULES.md](ARCHITECTURE_RULES.md) | Invariants, anti-patterns, enforcement |
| [docs/runtime_invariants.md](docs/runtime_invariants.md) | Core runtime laws that cannot be broken |
| [docs/architecture/runtime_spine.md](docs/architecture/runtime_spine.md) | Execution flow, commit protocol |

### Archival Documents

These documents were accurate at specific points in development but may not reflect current state:

| Document | Purpose | Baseline Date |
|----------|---------|---------------|
| [docs/runtime_baseline_36.md](docs/runtime_baseline_36.md) | Historical baseline | Pre-consolidation |
| [docs/runtime_baseline_38.md](docs/runtime_baseline_38.md) | Historical baseline | Pre-consolidation |

## Architectural Invariants

The following rules are enforced by `scripts/architecture_guard.py`:

### 1. Single Commit Authority

- Only `CommitCoordinator` may append events to the event store
- Only `CommitCoordinator` may mutate `WorldStateModel` via reducers
- Bypassing this path breaks replay determinism

### 2. Event Normalization

- All runtime event producers MUST use `DomainEventFactory`
- Events MUST include `commandKind`, `status`, and `notes` fields
- Raw `EventEnvelope` construction outside the factory is forbidden

### 3. Execution Boundary

- `VerifiedExecutor` is the ONLY layer that may produce side effects
- `VerifiedExecutor` MUST check preconditions before execution
- `VerifiedExecutor` MUST NOT commit state — only emit events

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

# Run all tests
swift test

# Build oracle product
swift build --product oracle
```

### CI Requirements

All PRs must pass:

1. `swift build --product oracle` completes offline
2. `swift test` — all tests pass
3. `scripts/architecture_guard.py` — no violations

## Evolution Process

To modify architectural invariants:

1. Open an issue describing the proposed change
2. Document the change in `ProjectMemory/architecture-decisions/`
3. Update `ARCHITECTURE_RULES.md` with new rules
4. Update affected authoritative documents
5. Update `scripts/architecture_guard.py` if enforcement changes
6. Get review from a maintainer
