# Runtime Bootstrap Pattern

## Pattern

Main-path runtime bootstrap owners (`MCPRuntimeHost`, `ControllerRuntimeBridge`) must use
`RuntimeBootstrap.makeBootstrappedRuntime(configuration:)` to obtain a fully-wired
`BootstrappedRuntime`.

`MCPDispatch` remains the public MCP entrypoint, but it delegates reusable runtime lifecycle
ownership to `MCPRuntimeHost` instead of owning an ad hoc cached runtime directly.

Standalone CLI tooling (`oracle doctor`, `oracle setup`) is an intentional
exception. Those utilities construct `DefaultProcessAdapter()` directly and run
outside the bootstrapped runtime.

## Rationale

Manual construction of `CommitCoordinator` allowed empty reducer arrays,
producing "fake" state that was never derived from events. The bootstrap
pattern ensures:

1. Real reducers are always wired
2. Commits return `CommitReceipt` with `snapshotID`
3. State is actually computed from events

## Example

```swift
// ✅ Correct: Use RuntimeBootstrap for main-path runtime surfaces
let bootstrapped = try await RuntimeBootstrap.makeBootstrappedRuntime(configuration: .live())
let container = bootstrapped.container
let orchestrator = bootstrapped.orchestrator

// ❌ Wrong: Manual construction with empty reducers
let coordinator = CommitCoordinator(eventStore: store, reducers: [])
```

## Enforcement

- `RuntimeKernelBootstrapTests` verifies the bootstrap returns real reducers
- Governance tests check that `MCPRuntimeHost` and `ControllerRuntimeBridge` are the direct bootstrap owners and that `MCPDispatch` delegates lifecycle ownership to `MCPRuntimeHost`
