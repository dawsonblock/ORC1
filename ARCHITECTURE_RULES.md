# Architecture Rules

This document is the normative invariant set for this checkout.

## Product Shape

Supported product surfaces are exactly:

- `OracleController`
- MCP server
- `oracle` CLI

No change may broaden the repo into a cross-platform runtime, hosted cloud service, or second primary execution framework.

## Main Execution Spine

The supported main-path execution spine is exactly:

`RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`

New runtime behavior must route through this spine unless it is an already-approved bounded exception documented below.

## MCP Boundary

- `MCPDispatch.handle(_ params: [String: Any])` is the outer compatibility seam only.
- After decode into `MCPToolRequest`, normal MCP dispatch must use typed transport (`JSONValue`, typed request helpers, typed payload structs).
- Internal MCP dispatch code must not introduce new raw `[String: Any]` transport or legacy dictionary probing after decode.
- MCP tool schemas must be authored as typed Swift schema values and exported to the legacy dictionary shape in one final conversion step.

## Side-Effect Authority

- Main-path environment mutation must flow through `VerifiedExecutor`.
- Main-path committed runtime state must flow through `CommitCoordinator`.
- Runtime code must not add new direct `Process()` spawning outside approved adapter boundaries.
- Process execution in runtime code must route through `ProcessAdapter` / `DefaultProcessAdapter`.
- `oracle setup` and `oracle doctor` remain explicit tooling-only exceptions outside the runtime spine.

## Controller Bridge

- The controller bridge must consume typed runtime outputs for core truth.
- It must not reintroduce legacy payload probing for action status, code execution, screenshots, or recipe progress when typed runtime fields already provide that information.
- The controller bridge is an adapter surface, not a second planner, executor, or commit authority.

## Experiment Isolation

`oracle_experiment_search` is an explicit bounded exception and is not part of the guaranteed main-path contract.

It must remain:

- isolated from `CommitCoordinator` mutation
- isolated from approval-store mediated promotion into the main runtime path
- isolated from live runtime state mutation
- confined to sandbox-local writeback only
- visibly separate from normal MCP dispatch/result flow

Worktree containment must reject traversal and symlink escape and must report cleanup outcome in result metadata.

## Persistence Exceptions

Recipe, workflow, and project-memory persistence are service-persistence surfaces, not alternate execution authorities. They may remain explicit bounded exceptions, but they must not expand into a second general execution path around the main runtime spine.

## Verification Honesty

Docs and status files must not claim:

- cross-platform runtime support
- production certification not backed by proof
- fully local reasoning when configured backends may be remote
- complete hardening beyond what code, tests, and guards prove
