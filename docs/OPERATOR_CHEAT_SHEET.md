# OracleOS Operator Cheat Sheet

This is the practical "what can I ask it to do?" guide for the current OracleOS checkout.

The supported surfaces are the controller app, the MCP server, and the `oracle` CLI. The supported runtime platform is macOS 14+ only.

## Best First Moves

Before asking for a multi-step task:

1. Ask for recipes first.
2. Ask for current context in the target app.
3. Ask it to find or inspect the exact element before clicking.
4. Ask it to wait for UI conditions instead of guessing with delays.

## High-Value Things To Ask

### 1. Orient in an app

Use this when you want to know what OracleOS can currently see.

Examples:

- "Get the current context in Chrome."
- "What window is active in Safari right now?"
- "Show me the running app and window state."

### 2. Find something before acting on it

Use this when you know the label, role, DOM id, or identifier of a target.

Examples:

- "Find the Compose button in Chrome."
- "Find the Save button in Xcode."
- "Find the element with DOM id :oq in Chrome."

### 3. Read what is visible

Use this when you need text from the app instead of screenshots.

Examples:

- "Read the visible text in the frontmost window."
- "Read the contents of the selected pane in Finder."
- "Read the message body in Mail."

### 4. Click, type, and press keys

Use this for direct UI interaction. Risky actions may pause for approval.

Examples:

- "Click the Send button in Chrome."
- "Type hello@example.com into the To field in Chrome."
- "Press Return in Chrome."
- "Send Command-L to Safari."

### 5. Focus apps and manage windows

Use this to bring the right target to the front or manipulate windows.

Examples:

- "Focus Slack."
- "Restore the Finder window."
- "Resize the Xcode window to 1400 by 900."

### 6. Wait for the UI to settle

Use this instead of sleep-based prompting.

Examples:

- "Wait until the URL contains github.com in Safari."
- "Wait until the Send button appears in Chrome."
- "Wait until the loading spinner is gone."

### 7. Take a screenshot or inspect coordinates

Use this for visual debugging or for bridging vision and AX.

Examples:

- "Take a screenshot of Chrome."
- "What element is at x 620, y 350?"
- "Take a screenshot of the frontmost app and summarize what actions are visible."

### 8. Use recipes for common multi-step flows

Use this whenever the task sounds repeatable.

Examples:

- "List available recipes."
- "Show the gmail-send recipe."
- "Run finder-create-folder with these parameters."

### 9. Fall back to visual grounding when AX is weak

Use this for Chrome or Electron-style UI where accessibility is incomplete.

Examples:

- "Visually ground the Compose button in Chrome."
- "Find the Send button visually inside this popup."
- "Parse the current screen through the vision sidecar."

### 10. Query or draft project memory

Use this for architecture decisions, known patterns, risks, and open problems.

Examples:

- "Query project memory for approval-store decisions."
- "Show memory about runtime orchestration boundaries."
- "Draft a risk memory about this patch strategy."

### 11. Review or compare change ideas

Use this when you want advisory engineering help rather than direct patch application.

Examples:

- "Run an architecture review for changes to RuntimeContainer and RuntimeOrchestrator."
- "Review this candidate patch for boundary violations."
- "Run sandbox experiments for these two patch candidates."

### 12. Mine and run workflows

Use this when you want to turn repeated traces into reusable workflows.

Examples:

- "Mine workflows for sending Gmail messages."
- "List available workflows."
- "Execute workflow abc123 with these parameters."

### 13. Use the CLI surface directly

Use this when you want setup, diagnostics, health, or the local dashboard.

Examples:

- "Run oracle status."
- "Run oracle doctor."
- "Start the MCP server."

## Reliable Prompt Patterns

### App orientation and action

```text
Get the current context in Chrome, find the Compose button, inspect it, then click it.
```

### Wait-based navigation

```text
Focus Safari, open github.com, and wait until the title contains GitHub before doing anything else.
```

### Web app form filling

```text
Find the To field in Chrome, type hello@example.com into it, tab to Subject, and type Weekly update.
```

### Screenshot-led debugging

```text
Take a screenshot of Chrome, summarize the visible actions, and identify the best click target for Compose.
```

### Sandbox engineering support

```text
Run an architecture review for these files, then compare two patch candidates in sandbox experiments.
```

## Things This Build Does Not Claim

- Cross-platform runtime support
- Cloud orchestration or hosted-agent behavior
- Guaranteed fully autonomous code repair
- Universal visual reliability in every app
- Direct workspace mutation from sandbox experiment search

## Related Docs

- [../README.md](../README.md)
- [PRODUCT_CONTRACT.md](PRODUCT_CONTRACT.md)
- [../ORACLE-MCP.md](../ORACLE-MCP.md)
- [MCP_TOOL_EXAMPLES.md](MCP_TOOL_EXAMPLES.md)