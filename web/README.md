# web — Dev Scaffolding (Not Connected to Runtime)

This directory contains a Vite + React frontend scaffold.

**Status:** Disconnected dev demo. `web/src/App.tsx` renders hardcoded mock data
with no real connection to the Swift OracleOS runtime.

This surface is not part of the production runtime path. It exists as a visual
prototype and is not wired to any live data source. Do not treat its displayed
values as ground truth about system state.

To make this surface useful, a real API bridge from the Swift runtime (e.g. a
local HTTP server or WebSocket feed from `RuntimeOrchestrator`) would need to
be built. That work has not been done.
