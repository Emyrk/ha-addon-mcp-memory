ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

USER root

# ---------------------------------------------------------------------------
# Patch the upstream dashboard to use RELATIVE URLs everywhere.
#
# The upstream HTML/JS ship root-absolute paths like `/api/...` and
# `/static/...`. Under HA Ingress the page is mounted at
# `/api/hassio_ingress/<token>/`, so root-absolute paths bypass the
# Ingress prefix and hit HA's own domain root → every API call 404s.
#
# Previous attempts used an nginx sub_filter layer to rewrite responses
# at proxy time. That worked in isolated curl tests but kept getting
# defeated by browser caches (constant ?v= query strings) and Content-Type
# mismatches. Patching the source at build time is dramatically simpler:
# relative URLs resolve against `document.baseURI`, which is the iframe
# URL under Ingress and the addon's host URL on the LAN. One config,
# both contexts.
# ---------------------------------------------------------------------------
ARG BUILD_VERSION=dev
COPY ingress-shim.html /tmp/ingress-shim.html
RUN set -eux; \
    cd /app/src/mcp_memory_service/web/static; \
    BUST="${BUILD_VERSION}-$(date +%s)"; \
    # ---- 1. Inject <base> shim at the top of <head>. ----
    # Reads window.location.pathname inside whatever iframe HA mounts us in
    # and pins document.baseURI to the iframe's directory. This works
    # regardless of what HA/Cloudflare/proxies do to baseURI.
    SHIM="$(tr -d '\n' < /tmp/ingress-shim.html)"; \
    awk -v shim="$SHIM" '/<head>/ && !done {print; print shim; done=1; next} 1' index.html > index.html.new \
        && mv index.html.new index.html; \
    # ---- 2. Strip root-absolute URLs so they become relative. ----
    # <base> only affects RELATIVE URLs; root-absolute (/static/, /api/)
    # still bypass it and hit the origin root, so we have to fix the
    # source paths too.
    sed -i 's|href="/static/|href="static/|g'             index.html; \
    sed -i 's|src="/static/|src="static/|g'               index.html; \
    sed -i 's|href="/api/|href="api/|g'                   index.html; \
    sed -i 's|href="/api-overview"|href="api-overview"|g' index.html; \
    sed -i "s|?v=10\\.7\\.1-auth-fix|?v=${BUST}|g"        index.html; \
    # ---- 3. app.js ----
    sed -i "s|this\\.apiBase = '/api'|this.apiBase = 'api'|g" app.js; \
    sed -i "s|fetch('/static/|fetch('static/|g"              app.js; \
    sed -i "s|fetch(\`/static/|fetch(\`static/|g"            app.js; \
    sed -i "s|fetch('/api/|fetch('api/|g"                    app.js; \
    sed -i "s|window\\.location\\.origin|document.baseURI|g" app.js; \
    sed -i "s|window\\.location\\.href = '/|window.location.href = '|g" app.js; \
    # ---- 4. Build-time assertions: fail loudly if any patch missed. ----
    grep -q "this.apiBase = 'api'"            app.js; \
    grep -q "document.baseURI"                app.js; \
    ! grep -q "this.apiBase = '/api'"         app.js; \
    ! grep -nE "fetch\\('/(api|static)/"      app.js; \
    grep -q "MCP_INGRESS_SHIM"                index.html; \
    grep -q "?v=${BUST}"                      index.html; \
    echo "[build] cache-buster: ${BUST}"

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
