# Oracle OS Architecture

This document describes the runtime shape that exists in this checkout.  
Normative requirements live in [ARCHITECTURE_RULES.md](ARCHITECTURE_RULES.md).

## Supported Surfaces

The supported product surfaces are:
MCP transport shape is intentionally split: `MCPDispatch.handle(_ params: [String: Any])` is the legacy JSON-RPC adapter seam, while normal MCP internals run on typed request and payload models (`JSONValue`, typed extractors, `Encodable` category payloads) and export once at the compatibility seam.

Supported surfaces:

- `OracleController` (native macOS operator UI)
- MCP server
- `oracle` CLI
- `oracle` CLI (`mcp`, `setup`, `doctor`, `dashboard`, `status`, `version`, `help`)

`oracle dashboard` is a non-interactive terminal dashboard snapshot within the CLI surface, not a separate host surface.

## Dominant Subsystems

The system reduces to five dominant layers:

| Layer | Role |
|-------|------|
| **Execution kernel** | Verified interaction with the environment |
| **Perception** | Reliable, compressed environment state via PerceptionEngine |
| **Planner** | Goal decomposition and action selection |
| **Evaluator (Critic)** | Detect failure and drive recovery |
| **Memory / Graph** | Persistent learning |

Everything else is supporting infrastructure.

## Layer Map

### RuntimeOrchestrator

Primary files:

- `Sources/OracleOS/Runtime/RuntimeOrchestrator.swift`
- `Sources/OracleOS/Runtime/RuntimeBootstrap.swift`
- `Sources/OracleOS/Runtime/RuntimeContext.swift`
- `Sources/OracleOS/Runtime/RuntimeExecutionDriver.swift`
- `Sources/OracleOS/Runtime/TaskContext.swift`

Responsibilities:

- route task/surface context
- build planner context from committed state plus optional workspace-scoped repository context
- evaluate policy
- call verified execution
- emit typed `DomainEvent` through `CommitCoordinator`
- receive `CommitReceipt` with `snapshotID` on commit
- own post-execution graph/memory/recovery updates
- fail closed on policy ambiguity

`RuntimeBootstrap.makeBootstrappedRuntime()` is the canonical kernel factory.
`MCPRuntimeHost` and `ControllerRuntimeBridge` are the direct main-path owners
that call this async factory to obtain a fully-wired `BootstrappedRuntime` with
recovery already completed.

On the live code path, `RuntimeOrchestrator` builds an explicit `PlannerContext` from the committed snapshot first, then enriches that context with a workspace-scoped `RepositorySnapshot` and at most five advisory `MemoryCandidate` values when a workspace root can be resolved from intent metadata or committed state. The memory influence remains bounded and advisory. Edit-capable planning still fails closed without a workspace root.

For the desktop surface, `OracleControllerHost` is a helper adapter only. It boots one runtime per app launch and forwards typed requests from the UI. It does not own planning, execution, or commit authority independently of `OracleOS`.

`MCPRuntimeHost` still eagerly binds `UnifiedMemoryStore` to the current workspace for compatibility with the explicit memory MCP tools, but that eager bind is no longer the canonical planner-context activation path.

The live controller/runtime result seam is typed internally. `RuntimeExecutionDriver` populates typed `ToolResult` payload views (`actionResult`, `traceResult`, `codeExecutionResult`, `recipeRunResult`) and `ControllerRuntimeBridge+Mapping` consumes those typed views directly. Legacy nested dictionaries remain compatibility/export transport only.

`OracleControllerShared` is split by stable contract boundaries: `ControllerModels.swift` for action/control/session models, `ControllerDiagnosticsModels.swift` for diagnostics and host state, and `ControllerTraceModels.swift` for trace, recipe, and dashboard payloads.

**CLI diagnostic exception:** `oracle setup` (SetupWizard) and `oracle doctor` (Doctor)
intentionally bypass the bootstrapped runtime — they construct `DefaultProcessAdapter()`
directly for interactive/diagnostic shell commands. They run outside the policy-checked
execution spine by design. See the EXECUTION AUTHORITY NOTE comments at the top of
`Sources/oracle/Doctor.swift` and `Sources/oracle/SetupWizard.swift`.

**Controller wait exception:** The desktop Wait action is observational. `OracleControllerHost`
currently evaluates it through `WaitManager.waitFor(...)` instead of sending it into
`VerifiedExecutor`, because it checks a condition rather than committing side effects.

The `BootstrappedRuntime` bundle contains:

- `RuntimeContainer`: All 18+ shared services (kernel + observability + memory)
- `RuntimeOrchestrator`: Linear runtime coordination
- `RecoveryReport`: Proof of startup recovery (WAL entries replayed, events recovered)

`RuntimeContext` is a compile-time boundary guard only — empty class body, never instantiated.
`@available(*, unavailable)` extensions on it prevent execution-adjacent properties from being
re-introduced. It is not part of the live runtime; governance tests scan it for forbidden patterns.

### Observation and Planning State

Primary files:

- `Sources/OracleOS/WorldModel/Observation/*`
- `Sources/OracleOS/Planning/*`
- `Sources/OracleOS/WorldModel/*`

Responsibilities:

- build canonical observations
- fuse AX and browser signals conservatively
- abstract raw state into reusable planning state
- maintain world state model, state diffs, and state updates

### Observation Change Detector

Primary files:

- `Sources/OracleOS/WorldModel/ObservationChangeDetector.swift`
- `Sources/OracleOS/WorldModel/ObservationDelta.swift`

Responsibilities:

- detect fine-grained element-level changes between consecutive observations
- produce ``ObservationDelta`` describing added, removed, and mutated elements
- enable delta-driven world model updates instead of full rebuilds
- reduce observation processing cost during long runtime sessions

Pipeline:

```
previous observation
↓
ObservationChangeDetector.detect(previous:incoming:)
↓
ObservationDelta
↓
StateDiffEngine (includes delta when previous observation available)
↓
WorldStateModel.apply(diff:)
```

By capturing only what changed at the element level, downstream consumers
skip re-processing thousands of unchanged elements each loop iteration.
During long runs with mostly stable UI this can reduce observation cost by
an order of magnitude.

### State Abstraction Engine

Primary files:

- `Sources/OracleOS/StateAbstraction/StateAbstractionEngine.swift`

Responsibilities:

- map raw AX / DOM elements to semantic types (`SemanticElement`)
- deduplicate similar elements
- attach intent labels
- produce minimal `CompressedUIState` for the planner

The planner should never read raw AX trees directly. Instead it receives
compressed state objects such as `Button("Send")`, `Input("Search")`, or
`List("Messages")`. This dramatically reduces reasoning token consumption
and improves planner stability.

### Action Schema System

Primary files:

- `Sources/OracleOS/ActionSchema/ActionSchema.swift`

Responsibilities:

- define typed action schemas with explicit preconditions and postconditions
- provide canonical schema library (`ActionSchemaLibrary`)
- verify preconditions against compressed UI state
- enable planners to operate on stable primitives

The planner should never emit raw instructions like `move mouse to 840, 410`.
It should always emit schemas such as `Click(Button("Send"))`. The executor
resolves the actual coordinates.

### Planning

Primary files:

- `Sources/OracleOS/Planning/*`

Responsibilities:

- interpret goals
- choose OS, code, or mixed planning path
- prefer graph-backed steps when available
- stay out of execution internals

### Skills

Primary files:

- `Sources/OracleOS/Skills/OS/*`
- `Sources/OracleOS/Code/Skills/*`
- `Sources/OracleOS/Browser/Skills/*`

Responsibilities:

- compile bounded intents
- resolve semantic targets through ranking for OS actions
- resolve structured workspace actions for code tasks

They do not execute directly.

### Verified Execution

Primary files:

- `Sources/OracleOS/Execution/VerifiedExecutor.swift`
- `Sources/OracleOS/Execution/ExecutionOutcome.swift`

Responsibilities:

- policy validation for executable intents
- postcondition validation of execution results
- structured command routing via `CommandRouter` and the domain routers
- event emission for `CommitCoordinator`
- comprehensive failure classification for recovery

This is the execution truth boundary. Every main-path side effect must flow through
``VerifiedExecutor``. The experiment subsystem (`oracle_experiment_search`) is explicitly
exempt: it runs candidate patches in isolated git worktrees dispatched directly from
`MCPDispatch`, without involving `VerifiedExecutor` or `RuntimeOrchestrator`. The isolation
guarantee for experiments comes from the worktree boundary, explicit canonical containment checks,
and sandbox execution metadata (resolved roots, attempted paths, command list, cleanup outcome),
not policy approval.
``VerifiedExecutor`` returns ``ExecutionOutcome`` with events and artifacts;
``CommitCoordinator`` is the only entity that writes committed state, returning
``CommitReceipt`` as immutable proof of the commit.

> **Note:** ``VerifiedActionExecutor`` is removed from the runtime execution
> path. All new code must use ``VerifiedExecutor`` routed through
> ``RuntimeOrchestrator.submitIntent(_:)``.

**Process() containment:** All `Foundation.Process()` constructor calls are confined to
`Sources/OracleOS/Execution/DefaultProcessAdapter.swift` and
`Sources/OracleOS/Execution/DefaultProcessAdapter+Daemon.swift`. No other file in
`Sources/OracleOS/` constructs a `Process()` directly. The CLI tools (`oracle doctor`,
`oracle setup`) are the only exception — they call `DefaultProcessAdapter` directly without
going through `VerifiedExecutor`, as documented in their `EXECUTION AUTHORITY NOTE` headers.

### Event Typing and Commit Flow

Primary files:

- `Sources/OracleOS/Events/DomainEvent.swift`
- `Sources/OracleOS/Events/CommitReceipt.swift`
- `Sources/OracleOS/Events/CommitCoordinator.swift`

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
