> **[ARCHIVED]** This document covers repair passes 1–3. Passes 4–6 are recorded in [STATUS.md](STATUS.md). The current authoritative state is STATUS.md.
>
> The build and test statements below are historical claims from that repair pass, not current certification. Re-run [scripts/verify-build.sh](scripts/verify-build.sh) or local `swift build` / `swift test` in a supported environment for current evidence.

---

# Repair Summary — 11-Step Bounded Repair Pass

**Completed:** 2026-04-03  
**Branch:** `main`  
**Historical build note:** `swift build` completed in the environment used during that pass. This is not current proof for the repo today.

---

## Objective

Bring the oracle-os-merge-kernel-boundary codebase to a cleanly-buildable, architecturally coherent baseline. No feature additions — pure structural repair.

---

## Step-by-Step Summary

### Step 1 — Product Contract Document (`ORACLE-MCP.md`)
Created `ORACLE-MCP.md` listing all 30 MCP tool signatures with parameter tables and return types. Establishes the authoritative public surface of OracleOS for client integrations.

### Step 2 — MCPDispatch wiring (all 30 tools)
Wired all 30 MCP tools in `MCPDispatch.swift`. Previously only a subset had dispatch entries; the remainder returned `unimplemented`. Each tool now performs typed parameter extraction with explicit `JSONValue` boundary crossing.

### Step 3 — Guard scripts
Created/updated three guard scripts:
- `scripts/mcp_boundary_guard.py` — verifies all declared tools have dispatch entries (no silent gaps)
- `scripts/architecture_guard.py` — enforces module boundary rules
- `scripts/execution_boundary_guard.py` — enforces VerifiedExecutor boundary rules

### Step 4 — VerifiedExecutor header contract
Added a doc-comment header to `VerifiedExecutor` describing the contract: callers must provide a `// VERIFIED:` rationale comment at every call site. Prevents silent overclaim of executor capabilities.

### Step 5 — Architecture documentation
Refreshed `ARCHITECTURE.md` and `docs/architecture/runtime_spine.md` to reflect the post-merge module layout and runtime spine (`RuntimeBootstrap → BootstrappedRuntime → RuntimeContainer → RuntimeOrchestrator → VerifiedExecutor → CommandRouter`).

### Step 6 — Runtime invariants document
Created `docs/runtime_invariants.md` codifying the invariants the runtime spine must maintain across all operating modes. Referenced by architecture guard.

### Step 7 — ProductEnvironmentManager docs
Updated `docs/oracle-controller.md` with the product environment setup sequence, migration logic, and onboarding step machine.

### Step 8 — AXScanner.swift decomposition (1,048 lines → 7 files)
Split `Sources/OracleControllerHost/AXScanner.swift` into:
- `AXScanner.swift` — public API surface (~180 lines)
- `AXScanner+Observation.swift` — observation capture
- `AXScanner+Elements.swift` — element tree walking
- `AXScanner+Screenshot.swift` — screenshot capture
- `AXScanner+Menu.swift` — menu enumeration
- `AXScanner+Browser.swift` — browser DOM integration
- `AXScanner+Internal.swift` — private helpers (made internal for cross-file extension)

Historical build note: **Build completed in that pass environment (8.50s)**

### Step 9 — Monolith file decompositions

#### RootView.swift (2,228 lines → 8 files)
- `RootView.swift` — 166 lines (NavigationSplitView skeleton only)
- `RootView+Onboarding.swift` — `OnboardingOverlayView`
- `RootView+Control.swift` — `ControlWorkspaceView`, `ApprovalQueueCard`, `ActionComposerCard`, `ControlInspectorView`
- `RootView+Recipes.swift` — `RecipesWorkspaceView`, `RecipeEditorView`, `RecipeParameterRow`, `RecipeStepCard`, `RecipeInspectorView`, `stringBinding()`
- `RootView+Traces.swift` — `TracesWorkspaceView`, `TraceInspectorView`
- `RootView+Diagnostics.swift` — `DiagnosticsWorkspaceView`, `DiagnosticsInspectorView`
- `RootView+Health.swift` — `HealthWorkspaceView`, `HealthInspectorView`
- `RootView+Settings.swift` — `SettingsWorkspaceView`, `SettingsInspectorView`

#### ControllerStore.swift (1,011 lines → 6 files)
- `ControllerStore.swift` — 295 lines (class body: properties + `init` + `start()` + `String.nilIfBlank`)
- `ControllerStore+System.swift` — onboarding flow + system/data management
- `ControllerStore+Recipes.swift` — recipe CRUD + run operations
- `ControllerStore+Operations.swift` — refresh, health, diagnostics, approval, trace, IPC
- `ControllerStore+Internal.swift` — internal state helpers (event handling, model application)
- `ControllerStore+Copilot.swift` — mission control + chat (pre-existing, not modified)

#### ControllerRuntimeBridge.swift (929 lines → 4 files)
- `ControllerRuntimeBridge.swift` — 338 lines (class declaration + all public API methods)
- `ControllerRuntimeBridge+Mapping.swift` — core model mappers + recipe/locator dictionary helpers
- `ControllerRuntimeBridge+DiagnosticsMapping.swift` — diagnostics model mappers
- `ControllerRuntimeBridge+TraceMapping.swift` — trace event mapper

**Access control fix:** `private` on class members that need cross-file extension access was changed to `internal` (Swift default). Affected: `hostClient`, `productEnvironmentManager` in `ControllerStore`, and all `private func` helpers moved to extension files.

Historical build note: **Build completed in that pass environment (4.24s)**

### Step 10 — Vision Sidecar Contract
Created `Sources/OracleOS/Contracts/VisionSidecarContract.swift` — typed Swift boundary contract for the vision sidecar HTTP API:
- `VisionSidecarEndpoint` — canonical endpoint path constants
- `VisionGroundRequest/Response` — `/ground` endpoint types
- `VisionDetectRequest/Response`, `VisionDetectedElement` — `/detect` endpoint types
- `VisionParseRequest/Response` — `/parse` endpoint types
- `VisionHealthResponse` — `/health` endpoint types

Created `vision-sidecar/schema/endpoints.py` — Python-side canonical schema definitions matching the Swift contract. Single source of truth for both sides of the boundary.

### Step 11 — CI + Release Infrastructure
- Updated `.github/workflows/ci.yml` to run `python3 scripts/mcp_boundary_guard.py` before build/test
- Created `docs/RELEASE_CHECKLIST.md` — pre-release gate covering build, tests, guards, docs, security, versioning, and distribution
- Created this `REPAIR_SUMMARY.md`

---

## Files Changed Summary

| Category | Files modified/created |
|---|---|
| MCP dispatch | `MCPDispatch.swift`, `ORACLE-MCP.md` |
| Guard scripts | `mcp_boundary_guard.py`, `architecture_guard.py`, `execution_boundary_guard.py` |
| Architecture docs | `ARCHITECTURE.md`, `runtime_spine.md`, `runtime_invariants.md`, `oracle-controller.md` |
| AXScanner split (Step 8) | 7 files |
| RootView split (Step 9a) | 8 files |
| ControllerStore split (Step 9b) | 6 files (1 pre-existing) |
| ControllerRuntimeBridge split (Step 9c) | 4 files |
| Vision sidecar contract (Step 10) | 2 files |
| CI + release docs (Step 11) | 3 files |

**Total: 0 features added. 0 APIs removed. Build clean throughout.**

---

## Access Control Pattern Applied

When splitting Swift class methods into cross-file extensions:

> `private func` inside a class body → `func` (internal) in an extension file  
> `private struct/enum` at file scope → `struct/enum` (internal) in a new file  
> `private let/var` used cross-file → `let/var` (internal) in the class body

This is the correct Swift pattern: `private` restricts to the source **file**, not the type. Extensions in separate files use `internal` visibility.
