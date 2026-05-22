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
RUN set -eux; \
    cd /app/src/mcp_memory_service/web/static; \
    # Cache-buster: change the static file ?v= query on every build so HA's
    # frontend iframe is forced to refetch index.html/app.js/style.css.
    BUST="${BUILD_VERSION}-$(date +%s)"; \
    # ---- Strip root-absolute URLs in index.html so they become relative. ----
    # Combined with the <base href> injected by ingress_wrapper.py at
    # request time, these resolve correctly under both HA Ingress and
    # direct LAN access.
    sed -i 's|href="/static/|href="static/|g'             index.html; \
    sed -i 's|src="/static/|src="static/|g'               index.html; \
    sed -i 's|href="/api/|href="api/|g'                   index.html; \
    sed -i 's|href="/api-overview"|href="api-overview"|g' index.html; \
    sed -i "s|?v=10\\.7\\.1-auth-fix|?v=${BUST}|g"        index.html; \
    # ---- app.js ----
    sed -i "s|this\\.apiBase = '/api'|this.apiBase = 'api'|g" app.js; \
    sed -i "s|fetch('/static/|fetch('static/|g"              app.js; \
    sed -i "s|fetch(\`/static/|fetch(\`static/|g"            app.js; \
    sed -i "s|fetch('/api/|fetch('api/|g"                    app.js; \
    sed -i "s|window\\.location\\.href = '/|window.location.href = '|g" app.js; \
    # ---- Build-time assertions ----
    grep -q "this.apiBase = 'api'"            app.js; \
    ! grep -q "this.apiBase = '/api'"         app.js; \
    ! grep -nE "fetch\\('/(api|static)/"      app.js; \
    grep -q "?v=${BUST}"                      index.html; \
    echo "[build] cache-buster: ${BUST}"

# Drop in our ingress middleware wrapper.
COPY ingress_wrapper.py /opt/ingress_wrapper.py

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
