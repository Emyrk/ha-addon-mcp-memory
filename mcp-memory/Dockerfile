ARG BUILD_FROM
FROM ${BUILD_FROM}

ENV LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1

USER root

# Install nginx (full variant) for the Ingress path-rewriting reverse proxy.
# IMPORTANT: nginx-light DOES NOT include ngx_http_sub_module, so sub_filter
# directives are silently ignored. Use nginx-full (or nginx-extras).
RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx-full \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/lib/nginx /var/log/nginx /run \
 && nginx -V 2>&1 | tr ' ' '\n' | grep -q http_sub_module \
    || (echo "ERROR: nginx build missing http_sub_module" && exit 1)

COPY nginx.conf /etc/nginx/nginx.conf
COPY run.sh /run.sh
RUN chmod a+x /run.sh

ENTRYPOINT []
CMD ["/run.sh"]
