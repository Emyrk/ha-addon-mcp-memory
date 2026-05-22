# MCP Memory Service (Home Assistant add-on)

Wraps [doobidoo/mcp-memory-service](https://github.com/doobidoo/mcp-memory-service) — a persistent
memory backend for AI agents — as a Supervisor-managed add-on.

## Configuration

| Option | Default | Description |
|---|---|---|
| `backend` | `sqlite_vec` | Storage backend (`sqlite_vec`, `hybrid`, `cloudflare`). |
| `allow_anonymous` | `false` | If true, no auth required. Do **not** enable on an exposed LAN. |
| `api_key` | `""` | Static API key. If empty, the addon auto-generates one and persists it to `/share/mcp-memory/api_key`. |
| `oauth_enabled` | `false` | Enable the OAuth 2.1 server for external clients (e.g. claude.ai). Keys persist under `/share/mcp-memory/oauth/`. |
| `oauth_issuer` | `""` | Public OAuth issuer URL (e.g. `https://memory.example.com`). Only relevant when `oauth_enabled` is true. |
| `log_level` | `info` | `debug`, `info`, `warning`, `error`. |

The SQLite database lives at `/share/mcp-memory/memory.db` (visible via the `share` SMB share).

## Authentication

There are three layers that can apply:

1. **Through HA Ingress (sidebar panel)** — the addon's middleware sees the
   `X-Ingress-Path` header HA injects and auto-attaches the service API key
   to each request. Because you must already be logged into HA to reach the
   iframe, the dashboard *skips its login modal entirely* — same UX as
   nodered/zigbee2mqtt.
2. **Direct LAN access** (`http://<ha-host>:8000/`) — the dashboard requires
   the API key. The auto-generated value is logged once on first start and
   stored at `/share/mcp-memory/api_key` (readable via the `share` SMB share).
3. **External / OAuth clients** — set `oauth_enabled: true` and provide a
   stable public `oauth_issuer` URL. The addon will generate (or reuse) an
   RSA key pair under `/share/mcp-memory/oauth/` and enable upstream's
   OAuth 2.1 Dynamic Client Registration flow.

## Endpoints

- REST + web dashboard: `http://<ha-host>:8000/` (HA Ingress: sidebar panel)
- MCP streamable HTTP: `http://<ha-host>:8000/mcp`
- OAuth metadata (when enabled): `http://<ha-host>:8000/.well-known/oauth-authorization-server`

## Notes on Mux / external MCP clients

Configure Mux to talk to `http://<ha-host>:8000/mcp` with the API key:

```jsonc
{
  "servers": {
    "memory": {
      "transport": "http",
      "url": "http://<ha-host>:8000/mcp",
      "headers": { "X-API-Key": "<your-api-key>" }
    }
  }
}
```
