---
description: "Launch the ORC1 Repo Hardening agent for an evidence-tagged code-first audit; extraction first, blocker ranking before invasive patches."
name: "Run ORC1 Repo Hardening"
argument-hint: "Describe the ORC1 audit scope, subsystem, or boundary to inspect."
agent: "ORC1 Repo Hardening"
---

Use the ORC1 Repo Hardening agent for this repository.

Do extraction first.

Start with an evidence-tagged audit of the core runtime, MCP, experiment, guard, test, and proof-artifact surfaces named by the agent.

For every substantive claim, label it exactly as one of:

- confirmed by code
- confirmed by tests
- claimed by docs only
- unproven in current environment

Return:

1. repo identity
2. runtime spine
3. authority map
4. MCP audit
5. experiment audit
6. guard map
7. test map
8. drift map
9. risk map
10. overstated claims
11. strongest evidence
12. weakest proof edges
13. blocker ranking

Only after blocker ranking and code-based justification, continue to a blocker-first patch plan.
Do not begin invasive patches until the blocker order is justified from code.
