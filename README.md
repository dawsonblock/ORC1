# OracleOS

OracleOS is a local macOS agent runtime written in Swift. The supported human operator surface in this checkout is the native `OracleController` macOS app. The same runtime is also exposed through the MCP server and the `oracle` CLI for programmatic and utility use.

Historical rebuild, handoff, phase, and deployment documents are archived under [docs/archive](docs/archive). They are useful for archaeology, not as the current repo contract.

## What Is Live

- Main-path execution spine: `RuntimeBootstrap.makeBootstrappedRuntime()` -> `RuntimeOrchestrator.submitIntent(_:)` -> `MainPlanner.plan(intent:state:)` -> `VerifiedExecutor.execute(_:)` -> `CommandRouter` -> `UIRouter` or `CodeRouter` -> `CommitCoordinator.commit(_:)`
- Desktop operator UI: `OracleController` is the supported local control surface; `OracleControllerHost` is the bundled helper bridge that boots one runtime per app launch and forwards typed requests into that runtime
- MCP surface: 30 public `oracle_*` tools defined in `Sources/OracleOS/MCP/MCPTools.swift` and dispatched from `Sources/OracleOS/MCP/MCPDispatch.swift`
- MCP runtime lifecycle: `MCPDispatch` remains the public tool entrypoint, while `MCPRuntimeHost` owns reusable runtime bootstrap, reuse, and reset semantics for the MCP host process
- CLI: local setup, doctor, status, and related tooling commands
- Internal result boundary: live controller/runtime action, trace, code-execution, and recipe payloads use typed `ToolResult` views; legacy nested dictionaries remain compatibility export only
- Optional service edge: `vision-sidecar/` is an external sidecar boundary
- Demo-only surface: `web/` is disconnected scaffolding and not part of the supported runtime contract

## What This README Does Not Claim

- It is not a live build badge or release certificate. Canonical local proof comes from `bash scripts/verify-build.sh`, which writes evidence to `local/verify/latest/`. Canonical shared proof comes from the artifact published by `.github/workflows/ci.yml`.
- It is not a zero-warning guarantee. See [STATUS.md](STATUS.md) and [BASELINE.md](BASELINE.md) for the current evidence posture.
- It does not claim that every code path goes through the main executor. `oracle_experiment_search` is a deliberate exception path that evaluates candidate patches in isolated git worktrees.
- It does not claim that every controller affordance enters `VerifiedExecutor`. The desktop Wait action is an observational host-side condition check.

## Quick Start

**Requirements:** macOS 14+, Swift 6, Xcode command line tools, Accessibility and Screen Recording permissions for UI automation.

```bash
git clone https://github.com/dawsonblock/ORC1.git
cd ORC1
swift build
swift test
bash scripts/verify-build.sh
```

Controller app from source:

```bash
swift run OracleController
```

Xcode workspace entrypoint:

```bash
open OracleController.xcworkspace
```

Unsigned local controller build:

```bash
./scripts/build-controller-app.sh --configuration debug --skip-sign
```

The controller's core local-readiness contract is: permissions granted, host bridge reachable, and local Application Support storage writable. Vision sidecar setup and Claude-backed copilot support are optional extensions, not blockers for the manual operator surface.

CLI entrypoints:

```bash
./.build/debug/oracle setup
./.build/debug/oracle doctor
./.build/debug/oracle status
```

## Live Docs

- [STATUS.md](STATUS.md) — current repo state and known limits
- [docs/REPO_FACTS.md](docs/REPO_FACTS.md) — generated package, tree, and MCP inventory
- [ARCHITECTURE.md](ARCHITECTURE.md) — runtime model and execution spine
- [ORACLE-MCP.md](ORACLE-MCP.md) — public MCP tool catalog
- [BASELINE.md](BASELINE.md) — point-in-time baseline and evidence notes
- [AUDIT.md](AUDIT.md) — truth audit and cleanup findings
- [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md) — live product surface and guarantees
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) — release gate checklist
- [docs/archive](docs/archive) — archived rebuild, milestone, deployment, and handoff history

## MCP Surface Summary

OracleOS currently exposes 30 stable public MCP tools across 9 categories.

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

See [ORACLE-MCP.md](ORACLE-MCP.md) for the full tool list and signatures.

## Runtime Boundaries

Main-path effects flow through one auditable spine:

```text
RuntimeBootstrap
  -> RuntimeOrchestrator
  -> MainPlanner
  -> VerifiedExecutor
  -> CommandRouter
  -> UIRouter / CodeRouter
  -> events
  -> CommitCoordinator
```

Explicit exceptions:

- `oracle_experiment_search` bypasses `RuntimeOrchestrator` and `VerifiedExecutor` by design; isolation comes from worktree sandboxing
- `Sources/oracle/Doctor.swift` and `Sources/oracle/SetupWizard.swift` are tooling-only shell exceptions
- `vision-sidecar/` is an optional service boundary, not a committed-state authority

For the MCP surface, `MCPDispatch` is the single public entrypoint and `MCPRuntimeHost` is the only reusable runtime owner behind it.

## Repository Layout

```text
Sources/
  OracleOS/               runtime, planning, MCP, memory, execution core
  OracleController/       native controller UI
  OracleControllerHost/   controller host process
  OracleControllerShared/ shared action/control, diagnostics, and trace contracts
  oracle/                 CLI entrypoints
Tests/                    unit, governance, and eval suites
docs/                     live docs plus archived history
ProjectMemory/            ADRs, risks, roadmap, known-good patterns
recipes/                  replayable JSON workflows
scripts/                  build, packaging, guard, and verification helpers
vision-sidecar/           optional Python vision service
web/                      disconnected demo surface
```

`OracleControllerShared` is intentionally split by stable contract boundaries: `ControllerModels.swift` for action/control/session models, `ControllerDiagnosticsModels.swift` for diagnostics and host state, and `ControllerTraceModels.swift` for trace, recipe, and dashboard payloads.

## Development

```bash
swift build
swift test
bash scripts/verify-build.sh
python3 scripts/mcp_boundary_guard.py
python3 scripts/architecture_guard.py
python3 scripts/execution_boundary_guard.py
```

`bash scripts/verify-build.sh` is the canonical local proof path: it runs the three guard scripts, a release build, the full Swift test suite, and writes evidence to `local/verify/latest/`. `.github/workflows/ci.yml` runs the same verifier path and publishes that directory as the shared CI proof artifact.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor expectations and [docs/GOVERNANCE.md](docs/GOVERNANCE.md) for the normative governance contract.

## License

[MIT](LICENSE)
