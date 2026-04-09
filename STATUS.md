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
