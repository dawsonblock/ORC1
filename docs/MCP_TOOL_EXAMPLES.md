# OracleOS MCP Tool Examples

This is the tool-by-tool walkthrough for the 30 public MCP capabilities in the current OracleOS checkout.

Use [OPERATOR_CHEAT_SHEET.md](OPERATOR_CHEAT_SHEET.md) for fast prompting patterns. Use [../ORACLE-MCP.md](../ORACLE-MCP.md) for the catalog and runtime instructions.

## Perception Tools

### 1. `oracle_context`

Purpose: get current app, window, focused element, URL, and visible actions.

Example ask:

```text
Get the current context in Chrome.
```

### 2. `oracle_state`

Purpose: list running apps and windows.

Example ask:

```text
Show all running apps and their windows.
```

### 3. `oracle_find`

Purpose: find an element by query, role, DOM id, class, or identifier.

Example ask:

```text
Find the Send button in Chrome.
```

### 4. `oracle_read`

Purpose: read visible text content from a subtree or app.

Example ask:

```text
Read the visible text in the frontmost window.
```

### 5. `oracle_inspect`

Purpose: inspect one element's metadata before acting.

Example ask:

```text
Inspect the Compose button in Chrome.
```

### 6. `oracle_element_at`

Purpose: map screen coordinates back to an accessible element.

Example ask:

```text
Tell me what element is at x 620, y 350.
```

### 7. `oracle_screenshot`

Purpose: take a screenshot of an app or the frontmost window.

Example ask:

```text
Take a screenshot of Chrome.
```

## Action Tools

### 8. `oracle_click`

Purpose: click by query, role, DOM id, or coordinates.

Example ask:

```text
Click the Compose button in Chrome.
```

### 9. `oracle_type`

Purpose: type text at focus or into a located field.

Example ask:

```text
Type hello@example.com into the To field in Chrome.
```

### 10. `oracle_press`

Purpose: press a single key.

Example ask:

```text
Press Return in Chrome.
```

### 11. `oracle_hotkey`

Purpose: send a key combination.

Example ask:

```text
Send Command-L to Safari.
```

### 12. `oracle_scroll`

Purpose: scroll content in an app.

Example ask:

```text
Scroll down in Notes.
```

### 13. `oracle_focus`

Purpose: bring an app or window to the front.

Example ask:

```text
Focus Slack.
```

### 14. `oracle_window`

Purpose: list, move, resize, minimize, maximize, restore, or close windows.

Example ask:

```text
Restore the Finder window.
```

## Wait Tool

### 15. `oracle_wait`

Purpose: wait for URL, title, element, focus, or value conditions.

Example ask:

```text
Wait until the URL contains github.com in Safari.
```

## Recipe Tools

### 16. `oracle_recipes`

Purpose: list installed recipes.

Example ask:

```text
List available recipes.
```

### 17. `oracle_run`

Purpose: execute a recipe.

Example ask:

```text
Run the gmail-send recipe with these parameters.
```

### 18. `oracle_recipe_show`

Purpose: show recipe details.

Example ask:

```text
Show the gmail-send recipe.
```

### 19. `oracle_recipe_save`

Purpose: install a new recipe from JSON.

Example ask:

```text
Save this recipe definition.
```

### 20. `oracle_recipe_delete`

Purpose: delete a stored recipe.

Example ask:

```text
Delete the old slack-send recipe.
```

## Vision Tools

### 21. `oracle_parse_screen`

Purpose: experimental sidecar-backed full-screen parse.

Example ask:

```text
Parse the current Chrome screen.
```

### 22. `oracle_ground`

Purpose: visually ground a described element to screen coordinates.

Example ask:

```text
Find the Send button visually in Chrome.
```

## Project Memory Tools

### 23. `oracle_memory_query`

Purpose: query stored architecture decisions, patterns, risks, and open problems.

Example ask:

```text
Query project memory for approval-store decisions.
```

### 24. `oracle_memory_draft`

Purpose: draft a new project memory entry.

Example ask:

```text
Draft a risk memory about the runtime-core split.
```

## Experiment Tool

### 25. `oracle_experiment_search`

Purpose: run bounded patch experiments in isolated sandboxes and rank the results.

Example ask:

```text
Compare these two patch candidates in sandbox experiments.
```

Note: results are sandbox-only. They are not direct workspace commits.

## Architecture Tools

### 26. `oracle_architecture_review`

Purpose: advisory review for architectural risks and invariant drift.

Example ask:

```text
Run an architecture review for changes to RuntimeContainer and RuntimeOrchestrator.
```

### 27. `oracle_candidate_review`

Purpose: deep advisory review of one patch candidate.

Example ask:

```text
Review this specific patch candidate for boundary violations.
```

## Workflow Tools

### 28. `oracle_workflow_mine`

Purpose: synthesize candidate workflows from traces and telemetry.

Example ask:

```text
Mine workflows for sending Gmail messages.
```

### 29. `oracle_workflow_list`

Purpose: list available synthesized workflows.

Example ask:

```text
List available workflows.
```

### 30. `oracle_workflow_execute`

Purpose: execute the current applicable step of a synthesized workflow by ID.

Example ask:

```text
Execute workflow abc123 with these parameters.
```

## Practical Usage Notes

### Use recipes first for multi-step work

```text
List recipes first, then use one if it matches sending a Gmail message.
```

### Use context before actions

```text
Get the current context in Chrome, then find and inspect the Send button.
```

### Use wait instead of blind delays

```text
Wait until the loading indicator is gone, then click Continue.
```

### Use vision only when AX is not enough

```text
If oracle_find cannot locate Compose in Chrome, visually ground it instead.
```

## Related Docs

- [OPERATOR_CHEAT_SHEET.md](OPERATOR_CHEAT_SHEET.md)
- [../ORACLE-MCP.md](../ORACLE-MCP.md)
- [PRODUCT_CONTRACT.md](PRODUCT_CONTRACT.md)