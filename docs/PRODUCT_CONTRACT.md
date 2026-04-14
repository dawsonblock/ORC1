# OracleOS Product Contract

This file states the live product surface in this checkout. Historical rebuild, handoff, and phase docs live under [archive/](archive/) and are not current certification.

## Supported Platform

OracleOS is a **macOS 14+ local automation runtime**.

Execution is local on macOS. If configured, the reasoning layer may call local or remote OpenAI-compatible backends, but those optional backends are outside the execution authority path.

The supported Swift runtime build and test path is macOS-only. The runtime depends on Apple accessibility frameworks and the vendored AX layer in `Vendor/AXorcist`, so Linux is not a supported runtime platform for `swift build`, `swift test`, the controller app, or the MCP host runtime. Some repository-analysis or guard scripts may run on Linux, but that does not constitute supported runtime operation.

## Supported Surfaces

The supported surfaces in this checkout are:

| Surface | Entry point | Role | Timeout model | Proof source |
| --- | --- | --- | --- | --- |
| Controller app | `OracleController` plus `OracleControllerHost` | Native macOS operator UI over one bootstrapped runtime per app launch | Host lifecycle and controller readiness checks; outside MCP request budgets | `RuntimeKernelBootstrapTests`, `ExecutionBoundaryBehaviorTests`, `scripts/verify-build.sh` |
| MCP server | `MCPDispatch` plus `MCPRuntimeHost` | Programmatic tool surface over one reusable runtime | Explicit bootstrap timeout plus per-tool timeout in `MCPDispatch` | `MCPDispatchBehaviorTests`, `MCPToolCoverageTests`, `scripts/verify-build.sh`, `.github/workflows/ci.yml` |
| CLI | `oracle` | Local setup, diagnostics, dashboard snapshot, status, version, and help tooling | Per-command CLI invocation; outside MCP timeout budgets | `ExecutionBoundaryBehaviorTests`, `scripts/verify-build.sh` for non-interactive commands, `.github/workflows/ci.yml` |

`oracle mcp` launches the MCP server surface. The remaining supported CLI commands are standalone local tooling commands.

### Canonical CLI Command List

<!-- CLI_CONTRACT_START -->
primary: mcp, setup, doctor, dashboard, status, version, help
aliases:
    version: --version, -v
    help: --help, -h
<!-- CLI_CONTRACT_END -->

`oracle dashboard` is a non-interactive terminal dashboard snapshot, not a long-running alternate host surface.

`oracle setup` and `oracle doctor` remain supported standalone tooling commands, but the canonical automated proof path covers only the non-interactive CLI commands.

`OracleControllerHost` is the bundled helper adapter for the desktop UI. It boots one `OracleOS` runtime per app launch and forwards typed requests into that runtime. It is not a second planner, executor, or commit authority.

`OracleControllerShared` is intentionally split across `ControllerModels.swift`, `ControllerDiagnosticsModels.swift`, and `ControllerTraceModels.swift` so the shared desktop contract mirrors action/control, diagnostics/host state, and trace/recipe/dashboard ownership boundaries.

## Guaranteed Execution Spine

The guaranteed main-path execution spine for supported runtime effects is:

```text
RuntimeBootstrap
    -> RuntimeOrchestrator
    -> MainPlanner
    -> VerifiedExecutor
    -> CommandRouter
    -> UIRouter / CodeRouter
    -> CommitCoordinator
```

Surface code is a consumer of this spine, not a mutator of it.

On the live runtime path, `RuntimeOrchestrator` plans from committed state first and builds an explicit `PlannerContext` with a workspace-scoped repository snapshot plus a bounded advisory memory set when a workspace root is available from intent metadata or committed state. Edit-capable code actions remain fail closed when no workspace root can be resolved.

## Bounded Exceptions

The following exception surfaces are documented and are **not** part of the guaranteed main-path execution contract. Adding a new bypass requires updating this table, the owning code comments, and the relevant tests or guards.

| Surface | Contract lane | Mutability | Approval | Timeout model | Reason | Owning file(s) | Proof source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `oracle_screenshot` | Explicit exception | Read-only observation | Not required | AX timeout plus MCP bootstrap and tool timeout | Direct AX screenshot capture; no committed runtime state | `Sources/OracleOS/MCP/MCPDispatch.swift`, `Sources/OracleOS/WorldModel/Perception/AX/AXScanner+Screenshot.swift` | `MCPDispatchBehaviorTests`, `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |
| `oracle_wait` | Explicit exception | Read-only observation | Not required | Caller-supplied wait timeout plus MCP bootstrap and tool timeout | Host-local polling check; no committed runtime state | `Sources/OracleOS/MCP/MCPDispatch.swift`, `Sources/OracleOS/MCP/WaitManager.swift` | `MCPDispatchBehaviorTests`, `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |
| `oracle_parse_screen` | Explicit exception | Read-only observation | Not required | MCP bootstrap and tool timeout | Optional experimental sidecar-backed perception | `Sources/OracleOS/MCP/MCPDispatch.swift`, `Sources/OracleOS/WorldModel/Perception/Vision/VisionScanner.swift` | `MCPDispatchBehaviorTests`, `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |
| `oracle_ground` | Explicit exception | Read-only observation | Not required | MCP bootstrap and tool timeout | Optional experimental sidecar-backed grounding | `Sources/OracleOS/MCP/MCPDispatch.swift`, `Sources/OracleOS/WorldModel/Perception/Vision/VisionScanner.swift` | `MCPDispatchBehaviorTests`, `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |
| `oracle_experiment_search` | Explicit exception | Sandboxed candidate execution | Not part of main-path approval; result must remain sandbox-only | MCP bootstrap timeout plus extended experiment tool timeout | Runs worktree-scoped experiments without committing the main workspace | `Sources/OracleOS/MCP/MCPDispatch.swift`, `Sources/OracleOS/Execution/Experiments/ExperimentManager.swift` | `MCPDispatchBehaviorTests`, `ExperimentResultIsolationTests`, `execution_boundary_guard.py` |
| `oracle doctor` | Explicit exception | Tooling shell and diagnostics | Not applicable | Standalone CLI invocation; outside MCP timeout budgets | Standalone diagnostic utility outside `RuntimeBootstrap` | `Sources/oracle/Doctor.swift` | `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |
| `oracle setup` | Explicit exception | Tooling shell and setup | Not applicable | Standalone CLI invocation; outside MCP timeout budgets | Standalone setup utility outside `RuntimeBootstrap` | `Sources/oracle/SetupWizard.swift` | `ExecutionBoundaryBehaviorTests`, `execution_boundary_guard.py` |

## Unsupported Assumptions

OracleOS is not a cloud service, not a browser product, and not a general-purpose agent framework. It is intentionally scoped to bounded local macOS automation with explicit approval and execution boundaries.

## Not Guaranteed

- Linux runtime support for the supported Swift runtime build or host surfaces
- Cloud or distributed deployment claims
- All reasoning or model execution being local by default
- Broad autonomous software-engineering claims beyond the bounded local runtime surfaces in this checkout
- Generalized repair reliability or guaranteed patch correctness
- Production-hardening or production-readiness claims unless they are separately proven by a live evidence source in this repo

Candidate patching, repair ranking, and advisory code workflows in this checkout may be heuristic, advisory, or experimental. They do not by themselves prove patch applicability, semantic correctness, or automatic persistence.

## Live Guarantees

### 1. The MCP surface is bounded and implemented

OracleOS currently exposes 30 tools across 9 categories. Tool names are declared in `Sources/OracleOS/MCP/MCPTools.swift` and dispatched in `Sources/OracleOS/MCP/MCPDispatch.swift`.

The catalog and input schemas are defined as typed Swift models (`MCPToolDefinition`, `MCPToolInputSchema`, `MCPPropertySchema`), and category handlers return `Encodable` payloads through the shared typed export helper rather than assembling new nested dictionary payloads in-line.

At the outer request seam, `MCPToolRequest.decodeResult(from:)` requires an explicit request version and rejects missing or unsupported versions before dispatch. Raw legacy export remains confined to the single `mcpLegacyJSONObject(from:)` helper.

The guard script `scripts/mcp_boundary_guard.py` and `Tests/OracleOSTests/MCP/MCPToolCoverageTests.swift` enforce declared-tool coverage.

| Category | Count |
| --- | ---: |
| Perception | 7 |
| Actions | 7 |
| Wait | 1 |
| Recipes | 5 |
| Vision | 2 |
| Memory | 2 |
| Experiments | 1 |
| Architecture | 2 |
| Workflows | 3 |

See [../ORACLE-MCP.md](../ORACLE-MCP.md) for the user-facing tool catalog.

### 2. Desktop actions that enter the runtime are approval-gated when policy requires it

Risky actions such as click, type, press, hotkey, scroll, focus, window operations, and recipe steps marked `requiresApproval` pass through `PolicyEngine` and may be gated by `ApprovalStore`.

When a gated action pauses, the caller receives an `approval_request_id`. Resuming the action requires that token.

The controller's Wait action is not a side-effecting runtime action. It is an observational condition check handled by the host and therefore does not enter `VerifiedExecutor`.

### 3. The main runtime spine is stable for main-path effects

Behavioral proof for the main path is no longer only source-scan based. `Tests/OracleOSTests/Runtime/RuntimeKernelBootstrapTests.swift` submits a live intent through `RuntimeOrchestrator.submitIntent(_:)` and asserts commit-visible state, while `Tests/OracleOSTests/Governance/ExecutionBoundaryBehaviorTests.swift` exercises the live approval gate in `VerifiedExecutor`. `Tests/OracleOSTests/Runtime/RuntimePlannerContextInjectionTests.swift` proves that the live planner path can inject a workspace-scoped repository snapshot, surface bounded advisory project memory, fail closed on edit demotion without a workspace root, and fall back to the committed repository root when intent metadata is absent. Supported `.code` repository actions also preserve typed policy classification during policy evaluation, so `readFile` and `searchRepository` stay on the typed code path instead of being treated as arbitrary shell execution.

### 4. Side effects follow a three-tier taxonomy

| Tier | Scope | Examples |
| --- | --- | --- |
| **Gated** | User-approved desktop actions | click, type, hotkey through `VerifiedExecutor` |
| **Service** | Infrastructure persistence | traces, memory, graph, recipes, workflows, telemetry |
| **Read-only** | Observation and perception | AX inspection, screenshots, controller Wait checks, sidecar-backed perception |

`VerifiedExecutor` governs gated desktop actions. Service persistence remains in its own subsystems.

This means `oracle_screenshot`, `oracle_wait`, `oracle_parse_screen`, and `oracle_ground` are observation and perception tools, not commit-authority paths.

### 5. The live controller/runtime result seam is typed internally

The live controller/runtime result seam is typed internally. `ToolResult` exposes `actionResult`, `traceResult`, `codeExecutionResult`, and `recipeRunResult`, and the controller host mapping layer consumes those typed views directly. Legacy nested dictionaries remain only as compatibility export at the outer result seam.

The CLI-only setup and diagnostics paths follow the same rule. `oracle setup` and `oracle doctor` load Claude Desktop config through `ClaudeConfigFile` and obtain vision bridge status from `VisionBridge.sidecarStatus()` instead of re-parsing raw JSON or maintaining a second status truth.

### 6. Evidence must come from the canonical verifier path

Canonical local proof comes from [../scripts/verify-build.sh](../scripts/verify-build.sh) in a valid environment. The script is fail-fast, rejects unsupported non-macOS runtime verification, and writes environment, build, CLI smoke, test, and summary artifacts to `local/verify/latest/`.

The verifier runs `scripts/cli_contract_guard.py` alongside the existing boundary guards so the documented CLI command list, the `main.swift` switch, and the printed usage output cannot silently drift apart.

Canonical shared proof comes from `.github/workflows/ci.yml`, which runs the same verifier path and publishes `local/verify/latest/` as the `canonical-verify-evidence` CI artifact.

Repo-owned workflow roles are intentionally narrow: `.github/workflows/ci.yml` is canonical proof, `.github/workflows/architecture.yml` is supplemental enforcement, and `.github/workflows/controller-release.yml` validates unsigned controller build/package outputs on PRs and pushes while handling signed/notarized release packaging on version tags. Security scanners such as CodeQL, Codacy, and Frogbot are supplemental signals and are not part of the product-certification contract.

`controller-release.yml` is intentionally packaging-only. It must not be treated as a replacement for the canonical verifier or as an alternate build/test certification path.

Direct `swift build` and `swift test` remain useful local commands, but archived repair notes, milestone docs, checked-in diagnostics, and ad hoc command output are historical only. The current tree should not be described as a zero-warning build unless it has been re-verified through the supported verifier path.

## Additional Limits

- Vision grounding accuracy
- Workflow synthesis coverage from sparse trace history
- Sub-second automation latency on all macOS applications

## References

- [../README.md](../README.md) — repo overview and quick start
- [../STATUS.md](../STATUS.md) — current repo state and known limits
- [../ARCHITECTURE.md](../ARCHITECTURE.md) — runtime model and execution spine
- [../BASELINE.md](../BASELINE.md) — evidence posture and baseline notes
- [../AUDIT.md](../AUDIT.md) — forensic cleanup findings
- [../ORACLE-MCP.md](../ORACLE-MCP.md) — full MCP tool reference
- [architecture/runtime_spine.md](architecture/runtime_spine.md) — runtime spine reference
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) — live release gate checklist
- [BASELINE_REPAIR_PASS.md](BASELINE_REPAIR_PASS.md) — historical repair-pass record
- [../ProjectMemory/README.md](../ProjectMemory/README.md) — project memory conventions
