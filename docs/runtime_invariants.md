# Runtime Invariants

This document records the non-negotiable runtime architecture rules for Oracle-OS.

## Execution and side effects

1. `VerifiedExecutor.execute(_:)` is the only side-effect execution boundary.
2. Runtime entry adapters (controller/MCP/recipes/CLI integrations) must submit
   intents through `IntentAPI`/`RuntimeOrchestrator` instead of executing actions directly.
3. `ExecutionOutcome` must include domain events for both success and failure paths.

## State mutation

1. `CommitCoordinator.commit(_:)` is the only committed-state write path.
2. `commit(_:)` returns `CommitReceipt` — an immutable proof of commit containing
   `commitID`, `snapshotID`, event IDs, and sequence number range.
3. Empty commits throw `CommitError.emptyCommit` — no-op commits are forbidden.
4. Reducers are the only components allowed to derive new committed state from events.
5. Reducers must be **idempotent** — applying the same events twice produces the same state.
6. `WorldStateModel.snapshot` returns `WorldModelSnapshot` (immutable value type).
7. `StateSnapshot` holds `WorldModelSnapshot`, not a mutable reference.

## Event typing

1. `DomainEvent` is the typed event contract for reducer-safe decoding.
2. `DomainEventCodec.decode(from:)` maps `EventEnvelope` to strongly-typed events.
3. Seven event types: `intentReceived`, `planGenerated`, `commandExecuted`,
   `commandFailed`, `evaluationCompleted`, `uiObserved`, `memoryRecorded`.
4. Legacy event types (`CommandSucceeded`, `CommandFailed`) are mapped through the codec.

## Runtime bootstrap

1. `RuntimeBootstrap.makeDefault(configuration:)` is the canonical kernel factory.
2. All entry points (MCP, Controller Host, CLI) must use `RuntimeBootstrap`.
3. Manual construction of `CommitCoordinator` with empty reducers is forbidden.
4. The bootstrap wires real reducers: `RuntimeStateReducer`, `UIStateReducer`,
   `ProjectStateReducer`, `MemoryStateReducer`.

## Planning and orchestration

1. Planning terminates at `Command`; planners do not execute.
2. Runtime orchestration follows a linear flow:
   `Intent -> plan -> execute -> commit -> evaluate`.
3. `RuntimeOrchestrator.runOneCycle(_:)` emits typed events and returns `snapshotID`.
4. `RuntimeExecutionDriver` is an adapter (`ActionIntent -> Intent`) only.

## Regression policy

Any new code that bypasses these invariants is a correctness bug and should be
blocked by architecture integrity tests.
