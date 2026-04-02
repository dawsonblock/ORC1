# ADR-001: Runtime Consolidation

## Status

Accepted

## Date

2026-03-29

## Decision

Consolidate the Oracle-OS runtime to have one canonical execution path with
committed state that is verifiable.

## Changes

### 1. Typed Events (DomainEvent)

Introduced `DomainEvent` as the typed event contract for reducer-safe decoding.
Seven event types: `intentReceived`, `planGenerated`, `commandExecuted`,
`commandFailed`, `evaluationCompleted`, `uiObserved`, `memoryRecorded`.

`DomainEventCodec.decode(from:)` maps `EventEnvelope` to strongly-typed events.
Legacy event types (`CommandSucceeded`, `CommandFailed`) are mapped automatically.

### 2. CommitReceipt

`CommitCoordinator.commit(_:)` now returns `CommitReceipt` instead of void.
The receipt is an immutable proof of commit containing:

- `commitID` (UUID)
- `timestamp`
- `firstSequenceNumber` / `lastSequenceNumber`
- `eventIDs`
- `snapshotID`
- `summary`

Empty commits throw `CommitError.emptyCommit` — no-op commits are forbidden.

### 3. Immutable StateSnapshot

`StateSnapshot` now holds `WorldModelSnapshot` (immutable value type) instead
of a mutable `WorldStateModel` reference. This ensures snapshots are truly
frozen and cannot be mutated after creation.

`StateSnapshot` conforms to `Codable` and `Sendable` for safe serialization
and cross-actor transfer.

### 4. RuntimeBootstrap as Canonical Factory

`RuntimeBootstrap.makeDefault(configuration:)` is the canonical kernel factory.
All entry points (MCP, Controller Host, CLI) must use this factory.

The bootstrap wires real reducers:

- `RuntimeStateReducer` — increments cycleCount, tracks lastIntentID, lastCommandKind
- `UIStateReducer` — updates activeApplication, windowTitle, url, elementCount
- `ProjectStateReducer` — tracks buildSucceeded, failingTestCount
- `MemoryStateReducer` — appends knowledgeSignals, memoryKeys

Manual construction of `CommitCoordinator` with empty reducers is forbidden.

### 5. Idempotent Reducers

Reducers are now idempotent — applying the same events twice to the same
state produces the same result. This ensures replay-stability and makes
debugging deterministic.

### 6. RuntimeOrchestrator Emits Typed Events

`RuntimeOrchestrator.runOneCycle(_:)` now emits typed events through the
commit flow and returns the `snapshotID` from `CommitReceipt`.

## Reason

The previous architecture allowed multiple paths to create coordinators,
some with empty reducer arrays. This made it impossible to know if state
was "real" (actually derived from events) or just placeholder zeros.

By consolidating to one canonical path:

1. Every commit produces auditable proof (`CommitReceipt`)
2. Reducers always run and produce real state
3. Snapshots are truly immutable
4. Entry points cannot accidentally bypass the reducer chain

## Tradeoffs

- Slightly more ceremony to create a runtime (must use `RuntimeBootstrap`)
- Empty commits are now errors (tests using `commit([])` needed updating)
- Reducers must be idempotent (duplicate detection adds minor overhead)

## Affected Modules

- `Sources/OracleOS/Events/DomainEvent.swift` (new)
- `Sources/OracleOS/Events/CommitReceipt.swift` (new)
- `Sources/OracleOS/Events/CommitCoordinator.swift` (modified)
- `Sources/OracleOS/State/StateSnapshot.swift` (modified)
- `Sources/OracleOS/State/Stores/SnapshotStore.swift` (modified)
- `Sources/OracleOS/State/Reducers/*.swift` (modified)
- `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` (modified)
- `Sources/OracleOS/MCP/MCPDispatch.swift` (modified)
- `Sources/OracleControllerHost/ControllerRuntimeBridge.swift` (modified)

## Evidence

- All 638 tests pass
- Reducer purity tests confirm idempotency
- Architecture integrity tests guard bypass regressions

## Source Trace IDs

- RuntimeBootstrap: `RuntimeKernelBootstrapTests`
- CommitReceipt: `CommitCoordinatorTests`
- Reducer truth: `ReducerTests`
- Snapshot immutability: `StateSnapshotTests`
