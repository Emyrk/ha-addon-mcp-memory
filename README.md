# ha-addon-mcp-memory

Home Assistant add-on repository that packages [doobidoo/mcp-memory-service](https://github.com/doobidoo/mcp-memory-service)
as a Supervisor-managed add-on.

## Install

1. In Home Assistant: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**.
2. Add the URL of this repo.
3. Refresh the store, install **MCP Memory Service**, configure options, **Start**.

Data is persisted under `/share/mcp-memory/` so it survives add-on upgrades and rebuilds.

## Endpoints (after start)

- REST + dashboard: `http://<ha-host>:8000/`
- MCP (streamable HTTP / SSE): `http://<ha-host>:8765/mcp`
