# MCP Memory Service (Home Assistant add-on)

Wraps [doobidoo/mcp-memory-service](https://github.com/doobidoo/mcp-memory-service) — a persistent
memory backend for AI agents — as a Supervisor-managed add-on.

## Configuration

| Option | Default | Description |
|---|---|---|
| `backend` | `sqlite_vec` | Storage backend (`sqlite_vec`, `hybrid`, `cloudflare`). |
| `allow_anonymous` | `false` | If true, no auth required. Do **not** enable on an exposed LAN. |
| `api_key` | `""` | Static API key for REST/MCP clients. |
| `log_level` | `info` | `debug`, `info`, `warning`, `error`. |

The SQLite database lives at `/share/mcp-memory/memory.db` (visible via the `share` SMB share).

## Endpoints

- REST + web dashboard: `http://<ha-host>:8000/`
- MCP streamable HTTP: `http://<ha-host>:8765/mcp`
