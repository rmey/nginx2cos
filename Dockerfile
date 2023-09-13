FROM nginx:1.24.0

ENV NGINX_VERSION "1.24.0"
ENV NJS_VERSION   0.7.12

ENV PROXY_CACHE_MAX_SIZE "10g"
ENV PROXY_CACHE_INACTIVE "60m"
ENV PROXY_CACHE_VALID_OK "1h"
ENV PROXY_CACHE_VALID_NOTFOUND "1m"
ENV PROXY_CACHE_VALID_FORBIDDEN "30s"
ENV CORS_ENABLED 0
ENV DIRECTORY_LISTING_PATH_PREFIX ""

# We modify the nginx base image by:
# 1. Adding configuration files needed for proxying private S3 buckets
# 2. Adding a directory for proxied objects to be stored
# 3. Replacing the entrypoint script with a modified version that explicitly
#    sets resolvers.
# 4. Explicitly install the version of njs coded in the environment variable
#    above.

COPY nginx-s3-gateway/common/etc /etc
COPY nginx-s3-gateway/common/docker-entrypoint.sh /docker-entrypoint.sh
COPY nginx-s3-gateway/common/docker-entrypoint.d /docker-entrypoint.d/
COPY nginx-s3-gateway/oss/etc /etc

RUN set -eux \
    export DEBIAN_FRONTEND=noninteractive; \
    mkdir -p /var/cache/nginx/s3_proxy; \
    chown nginx:nginx /var/cache/nginx/s3_proxy; \
    chmod -R -v +x /docker-entrypoint.sh /docker-entrypoint.d/*.sh; \
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/debian/ $(echo $PKG_RELEASE | cut -f2 -d~) nginx" >> /etc/apt/sources.list.d/nginx.list; \
    apt-get update; \
    apt-get install --no-install-recommends --no-install-suggests --yes \
      curl \
      libedit2 \
      nginx-module-njs=${NGINX_VERSION}+${NJS_VERSION}-${PKG_RELEASE}; \
    apt-get remove --purge --auto-remove --yes; \
    rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/nginx.list
# Implement changes required to run NGINX as an unprivileged user
RUN sed -i "/^server {/a \    listen       8080;" /etc/nginx/templates/default.conf.template \
    && sed -i '/user  nginx;/d' /etc/nginx/nginx.conf \
    && sed -i 's#http://127.0.0.1:80#http://127.0.0.1:8080#g' /etc/nginx/include/s3gateway.js \
    && sed -i 's,/var/run/nginx.pid,/tmp/nginx.pid,' /etc/nginx/nginx.conf \
    && sed -i "/^http {/a \    proxy_temp_path /tmp/proxy_temp;\n    client_body_temp_path /tmp/client_temp;\n    fastcgi_temp_path /tmp/fastcgi_temp;\n    uwsgi_temp_path /tmp/uwsgi_temp;\n    scgi_temp_path /tmp/scgi_temp;\n" /etc/nginx/nginx.conf \
# Nginx user must own the cache and etc directory to write cache and tweak the nginx config
    && chown -R nginx:0 /var/cache/nginx \
    && chmod -R g+w /var/cache/nginx \
    && chown -R nginx:0 /etc/nginx \
    && chmod -R g+w /etc/nginx

EXPOSE 8080

USER nginx


