#!/usr/bin/env python3
"""Build-time patch for the upstream MCP Memory Service dashboard.

The upstream dashboard uses root-absolute URLs (`/api/...`, `/static/...`).
Under Home Assistant Ingress those bypass the per-session prefix and hit
HA's domain root → 404.

We patch index.html + app.js to use a runtime-injected `window.__MCP_BASE__`
global (set by ingress_wrapper.py before app.js loads). On direct LAN
access the global is undefined → empty string → behaves like upstream.

Failures here SHOULD break the Docker build: an unpatched dashboard would
ship 404s in production.
"""

from __future__ import annotations

import os
import pathlib
import sys
import time

STATIC = pathlib.Path("/app/src/mcp_memory_service/web/static")
INDEX = STATIC / "index.html"
APP_JS = STATIC / "app.js"

BUILD_VERSION = os.environ.get("BUILD_VERSION", "dev")
BUST = f"{BUILD_VERSION}-{int(time.time())}"


def must_replace(text: str, old: str, new: str, *, where: str) -> str:
    """Substring replace that fails loudly if `old` was not present."""
    if old not in text:
        print(f"[patch] FAIL: {where!r} not found in source", file=sys.stderr)
        sys.exit(2)
    return text.replace(old, new)


def must_not_contain(text: str, needle: str, *, where: str) -> None:
    if needle in text:
        print(f"[patch] FAIL: leftover {where!r} → {needle!r}", file=sys.stderr)
        sys.exit(2)


# ---------- index.html ----------
html = INDEX.read_text(encoding="utf-8")
# Note: the build-time HTML patches mostly aren't required anymore because
# ingress_wrapper.py injects <base href>, but keeping them means direct LAN
# access (no Ingress) also works without relying on baseURI.
html = must_replace(html, 'href="/static/', 'href="static/', where="link /static href")
html = must_replace(html, 'src="/static/',  'src="static/',  where="script /static src")
html = must_replace(html, 'href="/api/',    'href="api/',    where="link /api href")
html = must_replace(
    html, 'href="/api-overview"', 'href="api-overview"',
    where="api-overview anchor",
)
html = must_replace(
    html, "?v=10.7.1-auth-fix", f"?v={BUST}",
    where="cache buster",
)
INDEX.write_text(html, encoding="utf-8")

# ---------- app.js ----------
js = APP_JS.read_text(encoding="utf-8")

# Rewrite the apiBase root so every fetch is an absolute URL under Ingress.
js = must_replace(
    js,
    "this.apiBase = '/api';",
    "this.apiBase = (window.__MCP_BASE__ || '') + '/api';",
    where="apiBase init",
)

# Fetches that build URLs from string literals.
js = must_replace(
    js,
    "fetch('/static/i18n/en.json')",
    "fetch((window.__MCP_BASE__ || '') + '/static/i18n/en.json')",
    where="static i18n en fetch",
)
js = must_replace(
    js,
    "fetch('/api/languages')",
    "fetch((window.__MCP_BASE__ || '') + '/api/languages')",
    where="api/languages fetch",
)
js = must_replace(
    js,
    "fetch(`/static/i18n/${lang}.json`)",
    "fetch(`${window.__MCP_BASE__ || ''}/static/i18n/${lang}.json`)",
    where="static i18n by-lang fetch",
    # NOTE: appears twice in upstream — `replace_all` semantics via repeated
    # check below.
)
# Second occurrence of the same template literal.
if "fetch(`/static/i18n/${lang}.json`)" in js:
    js = js.replace(
        "fetch(`/static/i18n/${lang}.json`)",
        "fetch(`${window.__MCP_BASE__ || ''}/static/i18n/${lang}.json`)",
    )

# Bare `fetch('/api/health')` (without trailing parameters).
if "fetch('/api/health')" in js:
    js = js.replace(
        "fetch('/api/health')",
        "fetch((window.__MCP_BASE__ || '') + '/api/health')",
    )

# OAuth redirect.
js = must_replace(
    js,
    "window.location.href = '/oauth/authorize'",
    "window.location.href = (window.__MCP_BASE__ || '') + '/oauth/authorize'",
    where="oauth redirect",
)

# SSE base. The upstream call is:
#     new URL(`${this.apiBase}/events`, window.location.origin)
# Since this.apiBase is already absolute (we prefixed it), point the base
# at window.location.origin directly — that's still correct because
# `${apiBase}` now contains the ingress prefix.
# So no change needed here; verify it's still using window.location.origin.
if "new URL(`${this.apiBase}/events`, window.location.origin)" not in js:
    print("[patch] WARN: SSE URL construction not in expected form", file=sys.stderr)

# ---------- assertions ----------
must_not_contain(js, "this.apiBase = '/api';", where="unpatched apiBase")
must_not_contain(js, "fetch('/api/", where="unpatched fetch('/api/")
must_not_contain(js, "fetch('/static/", where="unpatched fetch('/static/")
must_not_contain(js, "fetch(`/static/", where="unpatched fetch(`/static/")
if "window.__MCP_BASE__" not in js:
    print("[patch] FAIL: __MCP_BASE__ guard missing", file=sys.stderr)
    sys.exit(2)
if f"?v={BUST}" not in html:
    print("[patch] FAIL: cache buster not applied to index.html", file=sys.stderr)
    sys.exit(2)

APP_JS.write_text(js, encoding="utf-8")
print(f"[patch] OK — cache-buster={BUST}")
