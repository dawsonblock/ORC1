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
Forbidden outside the executor and its commit flow:

- Direct writes to `worldState`, `taskLedger`, or runtime memory stores
  that bypass the verified execution pipeline
- Spawning processes, writing files, or mutating UI state without
  executor evidence

### R5 — Planners choose structure, never execute

Planners must not resolve exact UI targets, mutate files, execute commands,
or inline recovery mechanics. Planning produces intent; execution resolves
and acts.

### R6 — Authoritative world model

The planner reads **only** from committed world state
(`WorldStateModel.snapshot`). Three state layers exist:

| Layer | Description |
| ------- | ------------- |
| **Observed** | Raw perception data from `ObservationBuilder` |
| **Predicted** | Simulated by `PlanSimulator` before commitment |
| **Committed** | `WorldStateModel.snapshot` — the only layer planners read |

State advances only through delta-based updates via `apply(diff:)`.
Raw AX/DOM/filesystem artifacts must not reach the planner directly.

### R7 — Experimental vision boundary

Vision tools (`oracle_parse_screen`, `oracle_ground`) are experimental.
Normal runtime operation must succeed without them. Planners must not
depend on vision output. Vision is allowed only for debugging, offline
evaluation, and optional enrichment.

Vision sidecar output must conform to `VisionPerceptionContract`:
structured `VisionDetection` frames validated by `VisionContractValidator`
before the world model accepts them. Raw untyped dictionaries are never
consumed directly.

### R8 — Canonical program graph

`ProgramKnowledgeGraph` is the canonical code model. All structural
code-intelligence graphs (`SymbolGraph`, `CallGraph`, `TestGraph`,
`BuildGraph`, `DependencyGraph`) are views over this single model.
Consumers should query code structure through `ProgramKnowledgeGraph`.

### R9 — Explicit repair pipeline

Code repair follows ordered stages: failure → localization → candidate
symbols → patch candidates → sandbox validation → regression check →
rank → apply. Localization is mandatory before patch generation.
Sandbox validation is mandatory before apply.

### R10 — Conservative learning

Workflow promotion requires **repeated critic-confirmed success** across
distinct episodes. One-off traces, sparse evidence, and unvalidated
patterns must not mutate planner policy or rewrite workflows.

### R11 — Lean traces

Traces store verified deltas — action proposals, executor results,
verification outcomes, and committed state changes. Full AX trees,
DOM snapshots, and large filesystem dumps are excluded from normal
traces and stored only in debug mode.

### R12 — Benchmark gating

Future upgrades must be evidence-driven. Core metrics (task success rate,
average steps, recovery count, wrong-target rate, patch success rate,
regression rate) are tracked by `MetricsRecorder`. Merges that degrade
core metrics are blocked until the regression is understood.

### R13 — Typed MCP after decode

`MCPDispatch.handle(_ params: [String: Any])` is the only supported raw MCP request seam.
After decode to `MCPToolRequest`, internal dispatch and category handlers must use
typed values (`JSONValue`, typed request extractors, `Encodable` payloads).
Do not introduce new internal `[String: Any]` transport in the normal MCP path.

### R14 — Single MCP legacy export seam

MCP category payloads must serialize through one shared typed export helper.
Do not add ad hoc dictionary assembly for workflow, memory, recipes, architecture,
or other typed MCP category responses.

### R15 — Experiment path isolation

`oracle_experiment_search` remains a bounded exception path:

- It is not part of the supported main execution spine.
- It must not mutate committed runtime state through `CommitCoordinator`.
- It must not use approval-store promotion as a backdoor into the main path.
- It must execute in sandbox worktrees with explicit containment checks and cleanup evidence.

### R16 — Process spawning boundary

Inside `Sources/OracleOS/`, raw `Process()` construction remains confined to
`DefaultProcessAdapter` and `DefaultProcessAdapter+Daemon`.
Do not introduce new process spawning points in runtime code.
CLI setup/doctor paths are explicit tooling exceptions and must remain outside
the bootstrapped runtime authority chain.

### R17 — Typed controller bridge truth

`ControllerRuntimeBridge` must consume typed `ToolResult` payload views
(`actionResult`, `traceResult`, `codeExecutionResult`, `recipeRunResult`) for
core truth. Legacy dictionary probing is compatibility-only and must not be
used to infer authoritative execution outcomes.

---

## Module Ownership

These are the live modules that own each functional domain. The five named coordinators
(ExecutionCoordinator, RecoveryCoordinator, DecisionCoordinator, LearningCoordinator,
StateCoordinator) do not exist in source and are not part of the live contract.

| Module | Owns | Does NOT own |
| -------- | ------ | -------------- |
| `RuntimeOrchestrator` | Intent intake, planner dispatch, lifecycle | Execution, state writes |
| `VerifiedExecutor` | All side-effecting execution | Planning, state building |
| `CommitCoordinator` | Committed state writes (returns `CommitReceipt`) | Planning, execution |
| `RecipeEngine` / `TraceRecorder` | Learning, outcome recording | Planning decisions, execution |
| `StateAbstractionEngine` | Observation, state abstraction | Execution, memory recording |

---

## Enforcement

These rules are enforced by governance tests under
`Tests/OracleOSTests/Governance/`. CI must pass all governance tests before
merge.

Governance test suites (all in `Tests/OracleOSTests/Governance/`):

- `ArchitectureFreezeTests` — R1, R3, R4, R5, protected modules
- `ExecutionBoundaryTests` — R4, R5, R7
- `ExecutionBoundaryEnforcementTests` — R4 enforcement
- `NoBypassExecutionTests` — R4
- `MemoryBoundaryTests` — R2
- `CodeIntelligenceBoundaryTests` — R8, R9
- `KnowledgePromotionTests` — R10
- `PlannerBoundaryTests` — R5
- `AgentLoopBoundaryTests` — Agent loop delegation
- `LayerImportRulesTests` — R3 import enforcement
- `RuntimeInvariantTests` — Runtime sequence invariants
- `StateMutationTests` — Committed state write authority
- `HardeningProofTests` — R13, R14, R15, R17 seam and typed-boundary assertions

---

## Freeze Policy

During active refactoring phases:

- No new subsystem directories under `Sources/OracleOS/`
- All new work routes into existing modules
- Architecture expansion requires matching eval coverage
