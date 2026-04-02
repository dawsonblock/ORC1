# Roadmap State

## Recently Completed

- **Runtime Consolidation** (2026-03-29)
  - Typed events via `DomainEvent` and `DomainEventCodec`
  - `CommitReceipt` returned from `commit()` with `snapshotID`
  - Immutable `StateSnapshot` using `WorldModelSnapshot` value type
  - `RuntimeBootstrap.makeDefault()` as canonical kernel factory
  - Idempotent reducers for replay-stability
  - MCP and Controller Host consolidated to use `RuntimeBootstrap`

## Current Focus

- Strengthen project memory retrieval and drafting
- Add bounded parallel experiment search for code tasks
- Add advisory-first architecture analysis and refactor proposals
- Workflow synthesis

## Deferred

- Neural policies
- Belief state
- Distributed execution
