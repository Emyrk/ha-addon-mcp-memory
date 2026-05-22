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

# Patches are applied by a Python script — shell + sed quoting got
# unmanageable once the JS replacements contained `||`, backticks, and
# template literals. The script also fails the build loudly if any
# expected upstream string is missing.
COPY patch_dashboard.py /tmp/patch_dashboard.py
RUN BUILD_VERSION="${BUILD_VERSION}" python3 /tmp/patch_dashboard.py

# Drop in our ingress middleware wrapper.
COPY ingress_wrapper.py /opt/ingress_wrapper.py

COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
