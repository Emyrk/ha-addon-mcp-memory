#!/usr/bin/with-contenv bashio
set -e

BACKEND="$(bashio::config 'backend')"
API_KEY="$(bashio::config 'api_key')"
LOG_LEVEL="$(bashio::config 'log_level')"

mkdir -p /share/mcp-memory

export MCP_MEMORY_STORAGE_BACKEND="${BACKEND}"
export MCP_MEMORY_SQLITE_PATH="/share/mcp-memory/memory.db"
export MCP_MEMORY_BACKUPS_PATH="/share/mcp-memory/backups"
export MCP_HTTP_HOST="0.0.0.0"
export MCP_HTTP_PORT="8000"
export MCP_SSE_HOST="0.0.0.0"
export MCP_SSE_PORT="8765"
export MCP_STREAMABLE_HTTP_MODE="1"
export LOG_LEVEL="${LOG_LEVEL^^}"

if [ -n "${API_KEY}" ]; then
    export MCP_API_KEY="${API_KEY}"
fi

if bashio::config.true 'allow_anonymous'; then
    bashio::log.warning "MCP_ALLOW_ANONYMOUS_ACCESS is enabled — anyone on your LAN can read/write memories."
    export MCP_ALLOW_ANONYMOUS_ACCESS="true"
fi

bashio::log.info "Starting MCP Memory Service (backend=${BACKEND})"
exec memory server --http --host 0.0.0.0 --port 8000
