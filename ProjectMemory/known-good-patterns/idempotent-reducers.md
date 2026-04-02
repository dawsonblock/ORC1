# Idempotent Reducer Pattern

## Pattern

Reducers must be idempotent — applying the same events twice to the same
state produces the same result.

## Rationale

Replay-stability is essential for debugging and deterministic testing.
If reducers accumulate state on every call (e.g., appending to arrays
without deduplication), replaying events produces different results.

## Implementation

Before adding to arrays like `notes` or `knowledgeSignals`, check if the
value already exists:

```swift
// ✅ Correct: Idempotent
let newNote = "lastIntentID=\(payload.intentID)"
guard !snapshot.notes.contains(newNote) else { return snapshot }
return snapshot.copy(notes: snapshot.notes + [newNote])

// ❌ Wrong: Not idempotent
return snapshot.copy(notes: snapshot.notes + ["lastIntentID=\(payload.intentID)"])
```

## Enforcement

- `ReducerPurityTests.test_replay_stable()` applies events twice and
  verifies the fingerprint is identical
