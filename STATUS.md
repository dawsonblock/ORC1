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
# Oracle OS Status Ledger

Last updated: 2026-04-09

This file is a current-state ledger, not a historical diary.
Archived repair chronology remains in `docs/archive/`.

## Proven Invariants

- Product shape is unchanged: supported runtime surfaces are `OracleController`, MCP server, and `oracle` CLI.
- Supported main-path spine remains:
  `RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`.
- MCP boundary is typed after decode:
  `MCPDispatch.handle(_ params: [String: Any])` is the raw ingress seam; internal MCP dispatch and category payloads use typed request/value models and `Encodable` response payloads.
- MCP tool catalog source-of-truth is now typed schema structs in `MCPTools.swift`, with one final legacy conversion helper.
- Controller bridge consumes typed runtime result views (`actionResult`, `traceResult`, `codeExecutionResult`, `recipeRunResult`) for core truth.
- Runtime execution driver now builds a typed transport payload before compatibility export.

## Bounded Exceptions (Explicitly Non-Main-Path)

- `oracle_experiment_search` remains a bounded sandbox exception (`MCPDispatch -> ExperimentManager -> ParallelRunner -> WorktreeSandbox`).
- Experiment path continues to bypass `RuntimeOrchestrator` and `VerifiedExecutor` by design.
- `oracle setup` and `oracle doctor` remain tooling exceptions outside bootstrapped runtime authority.
- Optional `vision-sidecar` remains non-core.

## Hardening Completed In This Pass

- Replaced MCP category result assembly in workflow/recipes/memory/architecture dispatch files with typed `Encodable` payload structs.
- Added shared typed-to-legacy MCP export seam helper and removed internal ad hoc category dictionary assembly.
- Converted MCP tool catalog source from dictionary literals to typed schema models.
- Hardened sandbox containment in `WorktreeSandbox.apply()` with stricter relative path validation plus symlink-aware path checks.
- Added experiment sandbox evidence metadata capture (canonical workspace root, resolved sandbox root, attempted paths, commands run, cleanup outcome).
- Replaced raw Claude config dictionary mutation in setup/doctor with typed config models backed by `JSONValue`, preserving unknown fields.

## Remaining Drift / Known Limits

- Full runtime build/test proof could not be executed in this environment because terminal execution is currently unavailable (`ENOPRO` workspace provider error), so only static error checks were run.
- Some compatibility seams still intentionally use dictionary transport (`ToolResult.data`, JSON-RPC boundary exports). This is expected at outer edges.
- Existing docs and archived materials outside the live contract may still contain historical detail not repeated here.

## Current Verification Posture

Validated in this pass:

- No static Swift errors reported by workspace diagnostics.
- Added governance assertions for:
  - typed MCP category serialization posture
  - typed MCP tool schema source-of-truth posture
  - typed controller bridge mapping posture
  - typed CLI config model usage posture
- Extended experiment isolation tests to cover sandbox metadata round-trip.
- Added MCP ingress seam test for missing-name decode failure.

Not validated in this pass (environment limitation):

- `swift build`
- `swift test`
- `bash scripts/verify-build.sh`
- `python3 scripts/cli_contract_guard.py`
- `python3 scripts/mcp_boundary_guard.py`
- `python3 scripts/architecture_guard.py`
- `python3 scripts/execution_boundary_guard.py`
