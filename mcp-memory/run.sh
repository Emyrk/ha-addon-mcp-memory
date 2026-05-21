#!/bin/bash
# Entrypoint that translates HA add-on options.json into env vars
# expected by mcp-memory-service, then execs the upstream binary.
set -e

OPTS=/data/options.json
get() {
    python3 -c "import json,sys; d=json.load(open('$OPTS')); v=d.get('$1', ''); print(v if not isinstance(v,bool) else ('true' if v else 'false'))"
}

BACKEND="$(get backend)"
API_KEY="$(get api_key)"
ALLOW_ANON="$(get allow_anonymous)"
LOG_LEVEL_RAW="$(get log_level)"
LOG_LEVEL="$(echo "${LOG_LEVEL_RAW:-info}" | tr '[:lower:]' '[:upper:]')"

mkdir -p /share/mcp-memory /share/mcp-memory/backups

export MCP_MEMORY_STORAGE_BACKEND="${BACKEND:-sqlite_vec}"
export MCP_MEMORY_SQLITE_PATH="/share/mcp-memory/memory.db"
export MCP_MEMORY_BACKUPS_PATH="/share/mcp-memory/backups"
export MCP_HTTP_HOST="0.0.0.0"
export MCP_HTTP_PORT="8000"
export MCP_SSE_HOST="0.0.0.0"
export MCP_SSE_PORT="8765"
export MCP_STREAMABLE_HTTP_MODE="1"
export LOG_LEVEL

if [ -n "${API_KEY}" ]; then
    export MCP_API_KEY="${API_KEY}"
fi

if [ "${ALLOW_ANON}" = "true" ]; then
    echo "[mcp-memory] WARNING: MCP_ALLOW_ANONYMOUS_ACCESS=true — anyone on your LAN can read/write memories." >&2
    export MCP_ALLOW_ANONYMOUS_ACCESS="true"
fi

echo "[mcp-memory] Starting (backend=${MCP_MEMORY_STORAGE_BACKEND}, log=${LOG_LEVEL})"
exec memory server --http --http-host 0.0.0.0 --http-port 8000
