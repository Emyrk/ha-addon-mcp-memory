ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

# Upstream image already ships mcp-memory-service + all native deps.
# We only add our entrypoint wrapper so options.json maps to env vars.
COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
