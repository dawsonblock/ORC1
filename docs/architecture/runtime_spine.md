# Oracle-OS Runtime Spine

## Enforced execution path

All side effects are expected to flow through this spine:

```text
Intent
  → RuntimeOrchestrator.submitIntent(_:)
  → Planner.plan(...) -> Command
  → VerifiedExecutor.execute(_:)
  → CommandRouter
  → DomainRouter (SystemRouter / UIRouter / CodeRouter)
  → Execution
  → ExecutionOutcome(events)
  → CommitCoordinator.commit(_:) -> CommitReceipt
  → DomainEventCodec decodes typed events
  → Reducers apply events to WorldStateModel
  → StateSnapshot (immutable WorldModelSnapshot)
  → evaluation
```

`RuntimeExecutionDriver` is an adapter that translates `ActionIntent` inputs into
typed `Intent` values and forwards them to `IntentAPI.submitIntent(_:)`.

## Runtime invariants

1. `VerifiedExecutor.execute(_:)` is the only execution boundary for side effects.
2. `CommitCoordinator.commit(_:)` returns `CommitReceipt` with `snapshotID`.
3. Empty commits throw `CommitError.emptyCommit`.
4. Reducers are pure, idempotent event-to-state derivation functions.
5. `ExecutionOutcome` must include events on success and failure paths.
6. `RuntimeOrchestrator` coordinates planning, execution, commit, and evaluation.
7. `RuntimeBootstrap.makeBootstrappedRuntime()` is the canonical kernel factory.
8. Recovery MUST complete before runtime becomes available to callers.
9. `RuntimeContainer` is the single authority for all shared services (18+ properties).
10. `RuntimeContext.init(container:)` is the only authorized context constructor.
11. `RuntimeContext.live()` is `@unavailable` — no split authority allowed.

## Event typing

`DomainEvent` defines the typed event contract:

| Event | Payload | Reducer |
|-------|---------|--------|
| `intentReceived` | intentID | RuntimeStateReducer |
| `planGenerated` | commandKind | RuntimeStateReducer |
| `commandExecuted` | status, notes | RuntimeStateReducer |
| `commandFailed` | error, commandKind | RuntimeStateReducer |
| `evaluationCompleted` | criticOutcome | RuntimeStateReducer |
| `uiObserved` | app, window, url, elementCount | UIStateReducer |
| `memoryRecorded` | category, key | MemoryStateReducer |

`DomainEventCodec.decode(from:)` maps raw `EventEnvelope` to typed events.
Legacy event types (`CommandSucceeded`, `CommandFailed`) are mapped automatically.

## Key modules

| Module | File | Responsibility |
|--------|------|---------------|
| API | `Sources/OracleOS/API/IntentAPI.swift` | Runtime intake boundary |
| Bootstrap | `Sources/OracleOS/Runtime/RuntimeBootstrap.swift` | Canonical kernel factory with async recovery |
| Container | `Sources/OracleOS/Runtime/RuntimeContainer.swift` | Single authority for 18+ shared services |
| Context | `Sources/OracleOS/Runtime/RuntimeContext.swift` | Peripheral services (from container) |
| Orchestration | `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift` | Linear runtime coordination |
| Planning | `Sources/OracleOS/Planning/MainPlanner+Planner.swift` | Intent -> Command planning |
| Execution | `Sources/OracleOS/Execution/VerifiedExecutor.swift` | Policy + routed command execution |
| Process | `Sources/OracleOS/Execution/DefaultProcessAdapter.swift` | Safe process execution with timeouts |
| Routing | `Sources/OracleOS/Execution/Routing/*.swift` | CommandRouter + domain router boundaries |
| Events | `Sources/OracleOS/Events/EventStore.swift` | Append-only event history |
| WAL | `Sources/OracleOS/Events/CommitWAL.swift` | Write-ahead log for crash recovery |
| DomainEvent | `Sources/OracleOS/Events/DomainEvent.swift` | Typed event contract + codec |
| CommitReceipt | `Sources/OracleOS/Events/CommitReceipt.swift` | Immutable commit proof |
| Commit | `Sources/OracleOS/Events/CommitCoordinator.swift` | Number/append/reduce + WAL recovery |
| Reducers | `Sources/OracleOS/State/Reducers/*.swift` | Pure, idempotent state derivation |
| Snapshot | `Sources/OracleOS/State/StateSnapshot.swift` | Immutable state capture |
| SnapshotStore | `Sources/OracleOS/State/Stores/SnapshotStore.swift` | Append-only snapshot history |

## Bootstrap flow

```text
Entry point (Controller / MCP / CLI)
  → RuntimeBootstrap.makeBootstrappedRuntime()
  → RuntimeContainer created with all 18+ services
  → CommitCoordinator.recoverIfNeeded()
  → RecoveryReport returned (WAL entries, events replayed)
  → BootstrappedRuntime bundle returned
  → RuntimeContext.init(container:) for peripheral services
  → Runtime ready for intents
```

### Recovery guarantees

- WAL is replayed idempotently (duplicate entries are safe)
- `recoverIfNeeded()` is idempotent (multiple calls return cached report)
- Recovery completes BEFORE `makeBootstrappedRuntime()` returns
- `RecoveryReport` is stored in `RuntimeContainer.recoveryReport`

### Process execution safety

`DefaultProcessAdapter` provides hardened process execution:

- Concurrent pipe draining prevents deadlock (pipes read WHILE process runs)
- 60-second default timeout with graceful termination
- 10MB bounded output prevents memory exhaustion
- `runWithTimeout()` async and `runSync()` dispatch-queue variants

## Remaining hardening focus

- Keep `AgentLoop` intake-only and free of planning/execution logic.
- Keep all user-facing entrypoints (controller/CLI/MCP/recipes) on the same
  `IntentAPI -> RuntimeOrchestrator` path via `RuntimeBootstrap.makeBootstrappedRuntime()`.
- Continue expanding architecture integrity tests that guard bypass regressions.
- Ensure all new entry points use async bootstrap with recovery.
