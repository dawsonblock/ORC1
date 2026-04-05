# Oracle Controller

Oracle Controller is the native local operator console for Oracle OS.

It now supports both developer and packaged-app flows:

- SwiftPM/Xcode workspace development
- standalone `Oracle Controller.app`
- downloadable `Oracle-Controller-<version>.dmg`

## Components

- `OracleController`: SwiftUI macOS dashboard and supported operator surface
- `OracleControllerHost`: bundled helper executable started by the app; boots one `OracleOS` runtime and translates typed app requests into that runtime
- `OracleControllerShared`: typed IPC models shared by the app and the host, split across action/control/session, diagnostics/host state, and trace/recipe/dashboard contracts
- `OracleController.xcworkspace`: Xcode workspace entry point

## What It Does

- live snapshot-based monitor for the current app
- manual action control for focus, click, type, press, and scroll through the runtime, plus observational wait-condition checks
- recipe library with create, duplicate, edit, save, delete, and run
- trace session browser with per-step verification, hashes, and artifact links
- health panel for permissions, host bridge state, writable local storage, sidecar state, and controller data directories
- mission control summary with readiness KPIs, alerts, approvals, recent traces, and optional copilot status
- approvals and risky-action visibility
- guided onboarding for permissions and first-run setup
- diagnostics export and app-data reveal/reset actions
- optional vision bootstrap install and repair from the UI
- optional local copilot guidance when Claude CLI is installed and configured

## Runtime Model

- one controller app launch starts one local host process
- one host process owns one runtime trace session
- the UI never calls heavy OracleOS APIs directly
- `OracleControllerHost` is an adapter layer, not a second runtime authority
- focus, click, type, press, scroll, and recipe work flow through `OracleControllerHost` into the bootstrapped runtime
- wait checks are host-local observations via `WaitManager`; they do not commit side effects or pass through `VerifiedExecutor`
- packaged builds write to `~/Library/Application Support/Oracle OS/`
- legacy `~/.oracle-os` data is migrated when present

## Local Readiness Model

The controller now treats local operator readiness as four separate facts instead of one generic status:

- permissions: Accessibility and Screen Recording are required for full control/monitoring
- host bridge: the app must be able to launch and talk to `OracleControllerHost`
- writable storage: Application Support, traces, recipes, approvals, project memory, experiments, and graph storage must be writable
- optional integrations: Vision bootstrap and local copilot setup are useful extensions, but not blockers for core operator readiness unless you have explicitly configured them and they become unavailable

Health, Mission Control, Control, and onboarding all surface these facts explicitly.

## Packaged App Layout

The packaged product is:

- `Oracle Controller.app`
- embedded helper: `Contents/Helpers/OracleControllerHost`
- bundled help/release notes/resources under `Contents/Resources/`
- optional bundled vision bootstrap assets under `Contents/Resources/VisionBootstrap/`

Primary user-owned storage:

- `~/Library/Application Support/Oracle OS/`
- `~/Library/Application Support/Oracle OS/Traces/`
- `~/Library/Application Support/Oracle OS/Recipes/`
- `~/Library/Application Support/Oracle OS/Approvals/`
- `~/Library/Application Support/Oracle OS/ProjectMemory/`
- `~/Library/Application Support/Oracle OS/Experiments/`
- `~/Library/Application Support/Oracle OS/Graph/`
- `~/Library/Application Support/Oracle OS/Vision/`
- `~/Library/Logs/Oracle OS/`

## First Launch

The first-launch wizard walks through:

1. product overview
2. Accessibility permission setup
3. Screen Recording permission setup
4. runtime readiness: bundled host availability, host bridge state, writable Application Support storage, and app-bundle mode
5. optional vision bootstrap setup
6. sample recipes and quick-start actions
7. ready-to-launch confirmation

## Opening It

### In Xcode

```bash
open OracleController.xcworkspace
```

Run the `Oracle Controller` or `Oracle Controller DMG` scheme from the workspace.

### From SwiftPM

```bash
swift run OracleController
```

If the controller cannot locate the host binary automatically, set:

```bash
export ORACLE_CONTROLLER_HOST_PATH="$PWD/.build/debug/OracleControllerHost"
```

### Build the packaged app and DMG

```bash
./scripts/build-controller-app.sh --configuration release
./scripts/create-controller-dmg.sh --configuration release
```

Unsigned development artifacts can be built with:

```bash
./scripts/build-controller-app.sh --configuration debug --skip-sign
./scripts/create-controller-dmg.sh --configuration debug --skip-sign
```

### Release signing and notarization

The release pipeline expects Developer ID and notary credentials.

Local notarization helper:

```bash
./scripts/notarize-controller-release.sh "dist/Oracle Controller.app"
./scripts/notarize-controller-release.sh dist/Oracle-Controller-*.dmg
```

CI automation lives in:

- `.github/workflows/controller-release.yml`

## Source Layout

The controller source is organized into focused extension files; no single file exceeds ~350 lines:

```text
Sources/OracleController/
  ControllerStore.swift              — @Observable class body: all state vars + init + start()
  ControllerStore+System.swift       — onboarding flow + system/data management
  ControllerStore+Recipes.swift      — recipe CRUD + run operations
  ControllerStore+Operations.swift   — refresh, health, diagnostics, approval, trace, IPC
  ControllerStore+Internal.swift     — internal helpers: event handling, model application
  ControllerStore+Copilot.swift      — mission control + chat
  RootView.swift                     — NavigationSplitView skeleton (~166 lines)
  RootView+Onboarding.swift          — OnboardingOverlayView
  RootView+Control.swift             — ControlWorkspaceView + action/approval cards
  RootView+Recipes.swift             — RecipesWorkspaceView, editor, inspector
  RootView+Traces.swift              — TracesWorkspaceView + TraceInspectorView
  RootView+Diagnostics.swift         — DiagnosticsWorkspaceView + inspector
  RootView+Health.swift              — HealthWorkspaceView + inspector
  RootView+Settings.swift            — SettingsWorkspaceView + inspector

Sources/OracleControllerHost/
  ControllerRuntimeBridge.swift              — public API (~338 lines)
  ControllerRuntimeBridge+Mapping.swift      — core model mappers
  ControllerRuntimeBridge+DiagnosticsMapping.swift  — diagnostics mappers
  ControllerRuntimeBridge+TraceMapping.swift — trace event mapper
```

**Access control note:** `private` members that need cross-file extension access use `internal` (Swift default). `private` in Swift is file-scoped, not type-scoped — methods in a separate extension file cannot see `private` members from the original file.

## Notes

- The controller is local-only and human-supervised.
- Risky actions still require explicit confirmation in the UI.
- Monitoring is low-frequency snapshot refresh, not streaming video.
- The app uses the existing recipe JSON schema and does not change MCP tool names.
- Vision is optional and experimental in the packaged product.
- Local copilot support is optional; the controller stays operator-ready without Claude CLI or Claude MCP setup.
- A configured optional integration should warn when unavailable; an unconfigured optional integration should read as optional, not broken.
