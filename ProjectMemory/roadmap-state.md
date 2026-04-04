# Roadmap State

## Recently Completed

- **Runtime Consolidation** (2026-03-29)
  - Typed events via `DomainEvent` and `DomainEventCodec`
  - `CommitReceipt` returned from `commit()` with `snapshotID`
  - Immutable `StateSnapshot` using `WorldModelSnapshot` value type
  - `RuntimeBootstrap.makeBootstrappedRuntime()` as canonical async factory for main-path surfaces
  - Idempotent reducers for replay-stability
  - MCP surface now routes reusable bootstrap ownership through `MCPRuntimeHost`; Controller Host still boots directly via `RuntimeBootstrap`

- **Typed Boundary Hardening** (2026-04-04)
  - `ToolResult` live controller/runtime seams now use typed payload views for action, trace, code-execution, and recipe results
  - `MCPRuntimeHost` is the explicit reusable lifecycle owner behind `MCPDispatch`
  - `OracleControllerShared` contracts are split across action/control, diagnostics, and trace/recipe/dashboard files
  - Full verification currently passes end to end (`swift test` and `scripts/verify-build.sh`)

## Current Focus

- Strengthen project memory retrieval and drafting
- Add bounded parallel experiment search for code tasks
- Add advisory-first architecture analysis and refactor proposals
- Workflow synthesis

## Deferred

- Neural policies
- Belief state
- Distributed execution
