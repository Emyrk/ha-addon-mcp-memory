"""Wrapper around mcp_memory_service's FastAPI app that handles HA Ingress.

The upstream dashboard ships absolute URLs like `/api/...`. Home Assistant
Ingress mounts the page under a per-session prefix (e.g.
`/api/hassio_ingress/<token>/`), which means absolute URLs bypass the
prefix and hit HA's domain root → every API call 404s.

HA developer docs recommend reading the `X-Ingress-Path` request header
and using it to rebuild URLs. We do that at the response layer:

  1. On every HTML response, if X-Ingress-Path is present, inject
     `<base href="<prefix>/">` right after `<head>` so the browser
     resolves *every* relative URL against the ingress prefix.
  2. The base tag is computed per-request, so it always matches the
     current Ingress token (tokens rotate).
  3. Direct LAN access doesn't send X-Ingress-Path, so the middleware
     is a no-op and the dashboard works at http://<host>:8000/ as usual.

This works because the dashboard's static files were already patched at
build time to use RELATIVE URLs (see Dockerfile). With <base href> set
server-side, those relative URLs resolve correctly under both contexts.
"""

import logging
import os
import sys

import uvicorn
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from mcp_memory_service.web.app import app

log = logging.getLogger("mcp-memory.ingress")


class IngressBaseHrefMiddleware(BaseHTTPMiddleware):
    """Inject <base href="${X-Ingress-Path}/"> into HTML responses."""

    async def dispatch(self, request, call_next):
        response = await call_next(request)

        content_type = response.headers.get("content-type", "")
        if "text/html" not in content_type.lower():
            return response

        ingress_path = request.headers.get("x-ingress-path", "")
        if not ingress_path:
            # Direct LAN access — no rewriting needed; relative URLs
            # already resolve against http://<host>:<port>/.
            return response

        # Strip trailing slash; we'll add one in the <base> href.
        ingress_path = ingress_path.rstrip("/")

        # Buffer the response body. index.html is ~70KB; non-issue.
        body = b""
        async for chunk in response.body_iterator:
            body += chunk

        # 1) <base href> for any <link>/<script>/<a> still using relative URLs.
        # 2) <meta name="mcp-ingress-prefix"> for diagnostics.
        # 3) An INLINE <script> that sets window.__MCP_BASE__ BEFORE app.js
        #    loads, so the patched app.js can build absolute fetch URLs.
        #    This is the bulletproof path: no relative URL resolution
        #    means nothing for HA/iframe/baseURI to interfere with.
        base_tag = (
            f'<base href="{ingress_path}/">'
            f'<meta name="mcp-ingress-prefix" content="{ingress_path}">'
            f'<script>window.__MCP_BASE__={ingress_path!r};'
            f'console.log("[mcp-memory] ingress base:", window.__MCP_BASE__);'
            f'</script>'
        ).encode("utf-8")

        # Inject right after the opening <head>. Case-insensitive in case
        # upstream ever ships a stylized tag.
        lowered = body.lower()
        head_idx = lowered.find(b"<head>")
        if head_idx == -1:
            log.warning("HTML response has no <head>; skipping rewrite")
        else:
            insert_at = head_idx + len(b"<head>")
            body = body[:insert_at] + base_tag + body[insert_at:]

        # Drop length/encoding/cache headers; Starlette will recompute
        # length, and we'll force no-cache so browsers refetch the HTML
        # after every addon update (the inline window.__MCP_BASE__ also
        # needs to reflect the current Ingress session token).
        new_headers = {
            k: v
            for k, v in response.headers.items()
            if k.lower()
            not in {
                "content-length",
                "content-encoding",
                "cache-control",
                "expires",
                "pragma",
                "etag",
                "last-modified",
            }
        }
        new_headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        new_headers["Pragma"] = "no-cache"
        new_headers["Expires"] = "0"
        return Response(
            content=body,
            status_code=response.status_code,
            headers=new_headers,
            media_type=content_type,
        )


app.add_middleware(IngressBaseHrefMiddleware)


def main():
    host = os.environ.get("MCP_HTTP_HOST", "0.0.0.0")
    port = int(os.environ.get("MCP_HTTP_PORT", "8000"))
    log_level = os.environ.get("LOG_LEVEL", "info").lower()
    print(
        f"[mcp-memory-ingress] uvicorn on {host}:{port} "
        f"(log={log_level}, X-Ingress-Path → <base href> injection enabled)",
        file=sys.stderr,
        flush=True,
    )
    uvicorn.run(app, host=host, port=port, log_level=log_level)


if __name__ == "__main__":
    main()
