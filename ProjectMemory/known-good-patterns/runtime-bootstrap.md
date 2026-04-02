# Runtime Bootstrap Pattern

## Pattern

All runtime entry points (MCP, Controller Host, CLI) must use
`RuntimeBootstrap.makeDefault(configuration:)` to obtain a fully-wired
`RuntimeContainer`.

## Rationale

Manual construction of `CommitCoordinator` allowed empty reducer arrays,
producing "fake" state that was never derived from events. The bootstrap
pattern ensures:

1. Real reducers are always wired
2. Commits return `CommitReceipt` with `snapshotID`
3. State is actually computed from events

## Example

```swift
// ✅ Correct: Use RuntimeBootstrap
let container = try RuntimeBootstrap.makeDefault(configuration: .live())
let orchestrator = RuntimeOrchestrator(container: container)

// ❌ Wrong: Manual construction with empty reducers
let coordinator = CommitCoordinator(eventStore: store, reducers: [])
```

## Enforcement

- `RuntimeKernelBootstrapTests` verifies the bootstrap returns real reducers
- Governance tests check that MCP and Controller use `RuntimeBootstrap`
