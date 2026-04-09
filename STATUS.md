# Oracle OS Status

This file is the current truth ledger for the repository.

## Proven Invariants

- The supported platform for the Swift runtime is macOS 14+.
- The supported product surfaces are `OracleController`, the MCP server, and the `oracle` CLI.
- The supported main-path execution spine is `RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`.
- MCP transport is typed after decode: the JSON-RPC edge may still use `[String: Any]`, but normal MCP dispatch now uses `MCPToolRequest`, `JSONValue`, typed category payload structs, and a shared export helper.
- MCP tool definitions are authored as typed Swift schema values and exported to the legacy MCP dictionary shape in one place.
- `oracle_experiment_search` remains a bounded side path and now records explicit sandbox evidence, canonical roots, executed commands, and cleanup outcome.
- The controller bridge maps from typed runtime payload views instead of nested legacy dictionary probing for core action/recipe/code-execution truth.
- `oracle setup` and `oracle doctor` remain tooling-only exceptions and now edit Claude config through a typed config model that preserves unknown fields.

## Bounded Exceptions

- `oracle_experiment_search`
- `oracle setup`
- `oracle doctor`
- optional `vision-sidecar`
- controller-host wait checks that remain observational rather than executor-driven

These are deliberate exceptions. They are not part of the guaranteed main-path execution contract.

## Known Remaining Drift

- The legacy MCP request adapter still defaults a missing request version to `"1"` for compatibility at the outer seam.
- Experiment trace projection in the controller still derives some sandbox display state from stored `TraceEvent` fields rather than from a richer typed experiment-trace contract.
- Recipe, workflow, and project-memory persistence remain bounded store-level exception surfaces rather than main-spine executor flows.

## Current Verification Posture

Passed in this session:

- `python3 scripts/cli_contract_guard.py`
- `python3 scripts/mcp_boundary_guard.py`
- `python3 scripts/architecture_guard.py`
- `python3 scripts/execution_boundary_guard.py`

Not fully runnable in this Linux session:

- `bash scripts/verify-build.sh` — intentionally fails because the supported runtime verification path is macOS 14+ only
- `swift test` — fails on Linux because Apple accessibility frameworks used by the vendored AX layer are unavailable
- full supported controller/MCP runtime proof — requires macOS 14+

Use `bash scripts/verify-build.sh` on macOS 14+ for the canonical local proof path.
