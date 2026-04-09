# Oracle OS Architecture

This document describes the runtime shape that exists in this checkout.  
Normative requirements live in [ARCHITECTURE_RULES.md](ARCHITECTURE_RULES.md).

## Supported Surfaces

The supported product surfaces are:

- `OracleController` (native macOS operator UI)
- MCP server
- `oracle` CLI

The CLI includes both supported runtime entry (`oracle mcp`) and explicit tooling-only exceptions (`oracle setup`, `oracle doctor`, dashboard/status/help/version commands).

## Main Execution Spine

The supported main-path execution spine is:

`RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

`RuntimeBootstrap.makeBootstrappedRuntime()` wires the shared runtime container and performs recovery before returning the bootstrapped bundle. `RuntimeOrchestrator.submitIntent(_:)` is the main-path intake that plans from committed state, executes through `VerifiedExecutor`, and commits durable state through `CommitCoordinator`.

## MCP Boundary

`MCPDispatch` is the single public MCP entry point and `MCPRuntimeHost` owns runtime reuse/reset for that surface.

The JSON-RPC seam still accepts and returns legacy `[String: Any]` dictionaries at the outer edge. After decode into `MCPToolRequest`, normal MCP dispatch uses:

- `JSONValue`
- typed request helpers
- typed category payload structs
- one shared typed export path back to the outer seam

`oracle_screenshot` and `oracle_experiment_search` remain explicit special handlers instead of being folded into the normal synchronous dispatch path.

## Controller Bridge

`OracleControllerHost` boots one runtime and forwards typed requests into it. `ControllerRuntimeBridge+Mapping` consumes typed runtime payload views (`actionResult`, `traceResult`, `codeExecutionResult`, `recipeRunResult`) instead of rebuilding core truth from legacy nested dictionaries.

`ControllerRuntimeBridge+TraceMapping` remains a typed projection from stored `TraceEvent` records into controller-facing trace models.

## Experiment Exception

`oracle_experiment_search` is a bounded side path:

`MCPDispatch -> ExperimentManager -> ParallelRunner -> WorktreeSandbox`

It is not part of the guaranteed main-path contract. It runs candidate patches in isolated git worktrees, records explicit sandbox evidence, reports cleanup outcome, and does not commit to the live workspace or the main runtime state.

Explicit experiment commands are typed as experiment-only requests and are materialized into executable `CommandSpec` values only inside the sandbox runner.

## Tooling Exceptions

`oracle setup` and `oracle doctor` remain outside the runtime bootstrap/orchestrator path. They are tooling-only helpers, not alternate runtimes. Their Claude config editing now uses a typed config model that preserves unknown JSON fields instead of mutating raw dictionary trees by hand.

## Verification Shape

The supported runtime proof path is macOS 14+ via:

- `swift build`
- `swift test`
- `bash scripts/verify-build.sh`
- `python3 scripts/cli_contract_guard.py`
- `python3 scripts/mcp_boundary_guard.py`
- `python3 scripts/architecture_guard.py`
- `python3 scripts/execution_boundary_guard.py`

This repository can still be audited on other platforms, but Apple-framework-dependent runtime proof remains macOS-only.
