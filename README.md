# OracleOS

OracleOS is a local macOS agent runtime written in Swift. This checkout exposes one main execution core plus three live surfaces: an MCP server, a native controller app, and the `oracle` CLI.

Historical rebuild, handoff, phase, and deployment documents are archived under [docs/archive](docs/archive). They are useful for archaeology, not as the current repo contract.

## What Is Live

- Main-path execution spine: `RuntimeBootstrap.makeBootstrappedRuntime()` -> `RuntimeOrchestrator.submitIntent(_:)` -> `MainPlanner.plan(intent:state:)` -> `VerifiedExecutor.execute(_:)` -> `CommandRouter` -> `UIRouter` or `CodeRouter` -> `CommitCoordinator.commit(_:)`
- MCP surface: 30 public `oracle_*` tools defined in `Sources/OracleOS/MCP/MCPTools.swift` and dispatched from `Sources/OracleOS/MCP/MCPDispatch.swift`
- Controller: native macOS UI for approvals, traces, recipes, diagnostics, and project memory
- CLI: local setup, doctor, status, and related tooling commands
- Optional service edges: `vision-sidecar/` is an external sidecar boundary; `web/` is a disconnected demo surface, not part of the runtime contract

## What This README Does Not Claim

- It is not a live build badge or release certificate. Run `swift build`, `swift test`, and `./scripts/verify-build.sh` for current evidence.
- It is not a zero-warning guarantee. See [STATUS.md](STATUS.md) and [BASELINE.md](BASELINE.md) for the current evidence posture.
- It does not claim that every code path goes through the main executor. `oracle_experiment_search` is a deliberate exception path that evaluates candidate patches in isolated git worktrees.

## Quick Start

**Requirements:** macOS 14+, Swift 6, Xcode command line tools, Accessibility and Screen Recording permissions for UI automation.

```bash
git clone https://github.com/dawsonblock/ORC1.git
cd ORC1
swift build
swift test
./scripts/verify-build.sh
```

Controller app from source:

```bash
open OracleController.xcworkspace
```

Unsigned local controller build:

```bash
./scripts/build-controller-app.sh --configuration debug --skip-sign
```

CLI entrypoints:

```bash
./.build/debug/oracle setup
./.build/debug/oracle doctor
./.build/debug/oracle status
```

## Live Docs

- [STATUS.md](STATUS.md) — current repo state and known limits
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
|---|---:|
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

## Repository Layout

```text
Sources/
  OracleOS/               runtime, planning, MCP, memory, execution core
  OracleController/       native controller UI
  OracleControllerHost/   controller host process
  OracleControllerShared/ shared models and protocols
  oracle/                 CLI entrypoints
Tests/                    unit, governance, and eval suites
docs/                     live docs plus archived history
ProjectMemory/            ADRs, risks, roadmap, known-good patterns
recipes/                  replayable JSON workflows
scripts/                  build, packaging, guard, and verification helpers
vision-sidecar/           optional Python vision service
web/                      disconnected demo surface
```

## Development

```bash
swift build
swift test
python3 scripts/mcp_boundary_guard.py
python3 scripts/architecture_guard.py
python3 scripts/execution_boundary_guard.py
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor expectations and [docs/GOVERNANCE.md](docs/GOVERNANCE.md) for the normative governance contract.

## License

[MIT](LICENSE)
