# Oracle OS Status

This file is the current truth ledger for the repository.

## Proven Invariants

- The supported platform for the Swift runtime is macOS 14+.
- The supported product surfaces are `OracleController`, the MCP server, and the `oracle` CLI.
- The supported main-path execution spine is `RuntimeBootstrap -> RuntimeOrchestrator -> MainPlanner -> VerifiedExecutor -> CommandRouter -> UIRouter / CodeRouter -> CommitCoordinator`.
- MCP transport is typed after decode: the JSON-RPC edge may still use `[String: Any]`, but normal MCP dispatch uses `MCPToolRequest`, `JSONValue`, typed category payload structs, and shared export helpers.
- MCP tool definitions are authored as typed Swift schema values and exported to the legacy MCP dictionary shape in one place.
- `oracle_experiment_search` remains a bounded side path and records explicit sandbox evidence, canonical roots, executed commands, and cleanup outcome.
- Experiment result ranking resolves equal-score ties through canonical candidate ordering rather than incidental candidate IDs or caller-supplied input order.
- Experiment diagnostics recover persisted search results from workspace roots derived from repository snapshots or sandbox paths and omit experiment execution metadata when persisted evidence is unavailable.
- The controller bridge maps from typed runtime payload views instead of nested legacy dictionary probing for core action, trace, recipe, and code-execution truth.
- Recipe, workflow, and project-memory persistence stay on explicit service-owned write authorities guarded by `scripts/execution_boundary_guard.py` instead of the main execution spine.
- `oracle setup` and `oracle doctor` remain tooling-only exceptions outside the bootstrapped runtime authority path.

## Bounded Exceptions

- `oracle_experiment_search`
- `oracle setup`
- `oracle doctor`
- optional `vision-sidecar`
- controller-host wait checks that remain observational rather than executor-driven

These are deliberate exceptions. They are not part of the guaranteed main-path execution contract.

## Current Verification Posture

Passed in this session:

- `bash scripts/verify-build.sh`
- `bash scripts/verify-build.sh --build-only`
- `python3 scripts/generate_repo_facts.py --check`
- `python3 scripts/cli_contract_guard.py`
- `python3 scripts/mcp_boundary_guard.py`
- `python3 scripts/architecture_guard.py`
- `python3 scripts/execution_boundary_guard.py`

Verified details from the canonical local proof surface:

- Environment: macOS 26.2, Apple Swift 6.3, Python 3.9.7
- Dependency resolution: passed
- Release build: passed
- Non-interactive CLI smokes: passed for `oracle version`, `oracle help`, `oracle status`, and `oracle dashboard`
- Full Swift test phase: passed via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`
- The end-to-end verifier completed the guard stage inside the canonical invocation and wrote a `=== VERDICT: PASS ===` summary to `local/verify/latest/verify-result.txt`

Verification notes:

- `scripts/verify-build.sh` now auto-prefers `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` via `xcrun` when full Xcode is installed. That is the working local proof path on this machine.
- The Command Line Tools-selected `swift` toolchain on this machine does not satisfy the full SwiftPM test path for this checkout by itself.
- The canonical local proof surface remains `local/verify/latest/`.

## Remaining Bounded Risks

- The repository is verifier-clean on the supported source proof path, but this file does not claim tagged release certification, signed controller packaging, or notarization beyond what `docs/RELEASE_CHECKLIST.md` and `.github/workflows/controller-release.yml` verify.
