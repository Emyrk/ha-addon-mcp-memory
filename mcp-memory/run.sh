#!/bin/bash
# Entrypoint that translates HA add-on options.json into env vars
# expected by mcp-memory-service, then execs the upstream binary.
set -e

OPTS=/data/options.json
get() {
    python3 -c "import json,sys; d=json.load(open('$OPTS')); v=d.get('$1', ''); print(v if not isinstance(v,bool) else ('true' if v else 'false'))"
}

BACKEND="$(get backend)"
USER_API_KEY="$(get api_key)"
ALLOW_ANON="$(get allow_anonymous)"
OAUTH_ENABLED="$(get oauth_enabled)"
OAUTH_ISSUER_OPT="$(get oauth_issuer)"
# DCR_KEY_OPT is read inside the OAUTH_ENABLED branch below.
LOG_LEVEL_RAW="$(get log_level)"
LOG_LEVEL="$(echo "${LOG_LEVEL_RAW:-info}" | tr '[:lower:]' '[:upper:]')"

mkdir -p /share/mcp-memory /share/mcp-memory/backups /share/mcp-memory/oauth

# ---------------------------------------------------------------------
# API key management
#
# Always have an API key set so:
#   * Direct LAN access is authenticated by default.
#   * Our ingress wrapper can inject the key when a request comes in
#     through HA Ingress, so the dashboard skips its login modal
#     (HA already authenticated the user to reach the iframe).
#
# Priority: addon options "api_key" > persisted file > auto-generate.
# ---------------------------------------------------------------------
KEY_FILE="/share/mcp-memory/api_key"
if [ -n "${USER_API_KEY}" ]; then
    EFFECTIVE_API_KEY="${USER_API_KEY}"
    echo "[mcp-memory] Using API key from addon options"
elif [ -s "${KEY_FILE}" ]; then
    EFFECTIVE_API_KEY="$(cat "${KEY_FILE}")"
    echo "[mcp-memory] Using persisted API key from ${KEY_FILE}"
else
    EFFECTIVE_API_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    umask 077
    printf '%s' "${EFFECTIVE_API_KEY}" > "${KEY_FILE}"
    echo "[mcp-memory] Auto-generated API key; persisted to ${KEY_FILE}"
    echo "[mcp-memory] First-run key (also visible at ${KEY_FILE}):"
    echo "[mcp-memory]   ${EFFECTIVE_API_KEY}"
fi
export MCP_API_KEY="${EFFECTIVE_API_KEY}"

export MCP_MEMORY_STORAGE_BACKEND="${BACKEND:-sqlite_vec}"
export MCP_MEMORY_SQLITE_PATH="/share/mcp-memory/memory.db"
export MCP_MEMORY_BACKUPS_PATH="/share/mcp-memory/backups"
export MCP_HTTP_HOST="0.0.0.0"
export MCP_HTTP_PORT="8000"
export MCP_SSE_HOST="0.0.0.0"
export MCP_SSE_PORT="8765"
export MCP_STREAMABLE_HTTP_MODE="1"
export LOG_LEVEL

if [ "${ALLOW_ANON}" = "true" ]; then
    echo "[mcp-memory] WARNING: MCP_ALLOW_ANONYMOUS_ACCESS=true — anyone on your LAN can read/write memories." >&2
    export MCP_ALLOW_ANONYMOUS_ACCESS="true"
fi

# ---------------------------------------------------------------------
# OAuth 2.1 authorization server (for external MCP clients like
# claude.ai). Only enable when the user opts in via the addon option,
# because for external use you also need a stable public issuer URL
# (typically via Cloudflare Tunnel).
#
# Keys are persisted to /share so JWTs survive container rebuilds.
# Without persistence, every restart would invalidate all tokens.
# ---------------------------------------------------------------------
if [ "${OAUTH_ENABLED}" = "true" ]; then
    OAUTH_DIR="/share/mcp-memory/oauth"
    OAUTH_PRIV="${OAUTH_DIR}/private_key.pem"
    OAUTH_PUB="${OAUTH_DIR}/public_key.pem"
    if [ ! -s "${OAUTH_PRIV}" ] || [ ! -s "${OAUTH_PUB}" ]; then
        echo "[mcp-memory] Generating RSA key pair for OAuth JWT signing..."
        umask 077
        python3 - "${OAUTH_PRIV}" "${OAUTH_PUB}" <<'PY'
import sys
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
priv_path, pub_path = sys.argv[1], sys.argv[2]
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
with open(priv_path, "wb") as f:
    f.write(key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ))
with open(pub_path, "wb") as f:
    f.write(key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ))
PY
        chmod 600 "${OAUTH_PRIV}"
        chmod 644 "${OAUTH_PUB}"
        echo "[mcp-memory] OAuth RSA keys generated in ${OAUTH_DIR}"
    else
        echo "[mcp-memory] Using existing OAuth RSA keys in ${OAUTH_DIR}"
    fi
    export MCP_OAUTH_ENABLED="true"
    export MCP_OAUTH_PRIVATE_KEY_PATH="${OAUTH_PRIV}"
    export MCP_OAUTH_PUBLIC_KEY_PATH="${OAUTH_PUB}"
    export MCP_OAUTH_STORAGE_BACKEND="sqlite"
    export MCP_OAUTH_SQLITE_PATH="${OAUTH_DIR}/oauth.db"
    if [ -n "${OAUTH_ISSUER_OPT}" ]; then
        export MCP_OAUTH_ISSUER="${OAUTH_ISSUER_OPT}"
    fi

    # Lock down Dynamic Client Registration so randoms can't even create
    # OAuth clients. Auto-generate a DCR key on first start and persist it
    # so it survives restarts. Clients must POST /oauth/register with
    # `Authorization: Bearer <dcr_key>` to register.
    DCR_KEY_FILE="${OAUTH_DIR}/dcr_key"
    DCR_KEY_OPT="$(get oauth_dcr_key)"
    if [ -n "${DCR_KEY_OPT}" ]; then
        export MCP_DCR_REGISTRATION_KEY="${DCR_KEY_OPT}"
        echo "[mcp-memory] DCR registration locked by addon-option key"
    elif [ -s "${DCR_KEY_FILE}" ]; then
        export MCP_DCR_REGISTRATION_KEY="$(cat "${DCR_KEY_FILE}")"
        echo "[mcp-memory] DCR registration locked by persisted key at ${DCR_KEY_FILE}"
    else
        GENERATED_DCR_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
        umask 077
        printf '%s' "${GENERATED_DCR_KEY}" > "${DCR_KEY_FILE}"
        export MCP_DCR_REGISTRATION_KEY="${GENERATED_DCR_KEY}"
        echo "[mcp-memory] Auto-generated DCR registration key; persisted to ${DCR_KEY_FILE}"
        echo "[mcp-memory] DCR key (give to OAuth clients during registration):"
        echo "[mcp-memory]   ${GENERATED_DCR_KEY}"
    fi
    echo "[mcp-memory] OAuth 2.1 enabled (issuer=${MCP_OAUTH_ISSUER:-auto})"
fi

echo "[mcp-memory] Starting (backend=${MCP_MEMORY_STORAGE_BACKEND}, log=${LOG_LEVEL})"
# Run via our ingress wrapper so HA Ingress's X-Ingress-Path header is
# injected as a per-request <base href> into the dashboard HTML.
# Direct LAN clients don't send X-Ingress-Path, so the wrapper is a
# no-op and the dashboard works at http://<host>:8000/ unchanged.
export PYTHONPATH=/app/src:${PYTHONPATH:-}
exec python3 /opt/ingress_wrapper.py
