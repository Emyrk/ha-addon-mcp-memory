ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# Base image is ghcr.io/home-assistant/<arch>-base-python (Alpine)
RUN apk add --no-cache \
        build-base \
        python3-dev \
        py3-pip \
        sqlite \
        sqlite-dev \
    && pip3 install --break-system-packages --no-cache-dir \
        "mcp-memory-service" \
    && apk del build-base python3-dev sqlite-dev

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]
