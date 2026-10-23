# syntax=docker/dockerfile:1
ARG PHP_VERSION=8.5
ARG FRANKENPHP_VERSION=1
ARG INSTALLER_VERSION=2.12.3
# zts when the fpm base is the same ZTS build as zts (PHP_SOURCE=src)
ARG FPM_EXT_BUILDER=nts

FROM mlocati/php-extension-installer:${INSTALLER_VERSION} AS installer-upstream

FROM --platform=$BUILDPLATFORM alpine:3 AS installer
COPY --from=installer-upstream /usr/bin/install-php-extensions /usr/bin/
# shortcut: installer rejects unreleased PHP minors; drop once it lists 8.6
RUN sed -i 's/| 805)/| 805 | 806)/' /usr/bin/install-php-extensions \
    && grep -q '| 806)' /usr/bin/install-php-extensions
FROM ghcr.io/php/pie:bin AS pie

FROM php:${PHP_VERSION}-zts-trixie AS ext-builder-zts
ARG EXTENSIONS
ARG REDIS_VERSION
ARG APCU_VERSION
ARG MONGODB_VERSION
ARG OPENTELEMETRY_VERSION
ARG PROTOBUF_VERSION
ARG GRPC_VERSION
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=bind,from=installer,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    /build/extensions.sh

FROM php:${PHP_VERSION}-fpm-trixie AS ext-builder-nts
ARG EXTENSIONS
ARG REDIS_VERSION
ARG APCU_VERSION
ARG MONGODB_VERSION
ARG OPENTELEMETRY_VERSION
ARG PROTOBUF_VERSION
ARG GRPC_VERSION
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=bind,from=installer,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    /build/extensions.sh

# hadolint ignore=DL3006
FROM ext-builder-${FPM_EXT_BUILDER} AS ext-builder-fpm

FROM --platform=$BUILDPLATFORM alpine:3 AS s6
ARG S6_OVERLAY_VERSION
ARG TARGETARCH
WORKDIR /tmp
RUN case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) exit 1 ;; esac \
    && url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}" \
    && mkdir /s6 \
    && for f in noarch "$arch"; do \
        wget -q "$url/s6-overlay-$f.tar.xz" "$url/s6-overlay-$f.tar.xz.sha256" \
        && sha256sum -c "s6-overlay-$f.tar.xz.sha256" \
        && tar -C /s6 -Jxpf "s6-overlay-$f.tar.xz" || exit 1; \
    done

FROM php:${PHP_VERSION}-zts-trixie AS cli
ARG PKG_STAMP
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-zts /out/ /
# hadolint ignore=DL3008,SC2086
RUN --mount=type=bind,from=ext-builder-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    apt-get update \
    && apt-get upgrade -y \
    && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps \
    && xargs apt-mark manual < /tmp/runtime-deps \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS \
    && xargs dpkg -s < /tmp/runtime-deps > /dev/null \
    && rm -rf /var/lib/apt/lists/* \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && find / -xdev -perm /6000 -type f -exec chmod ug-s {} +
COPY rootfs/common/ rootfs/php/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=1 \
    PHP_SESSION_COOKIE_HTTPONLY= \
    PHP_SESSION_USE_STRICT_MODE=0 \
    PHP_SESSION_COOKIE_SAMESITE=
WORKDIR /app
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php", "-a"]

FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-trixie AS frankenphp
ARG PKG_STAMP
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-zts /out/ /
# hadolint ignore=DL3008,SC2086
RUN --mount=type=bind,from=ext-builder-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    apt-get update \
    && apt-get upgrade -y \
    && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps \
    && xargs apt-mark manual < /tmp/runtime-deps \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS \
    && xargs dpkg -s < /tmp/runtime-deps > /dev/null \
    && rm -rf /var/lib/apt/lists/* \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && chmod 1777 /data /config /data/caddy /config/caddy \
    && find / -xdev -perm /6000 -type f -exec chmod ug-s {} + \
    # file caps stop frankenphp starting under --cap-drop ALL; a plain copy drops them
    && f=/usr/local/bin/frankenphp \
    && { setpriv --bounding-set=-all "$f" version >/dev/null 2>&1 || { cp "$f" "$f.new" && mv "$f.new" "$f"; }; } \
    && setpriv --bounding-set=-all "$f" version
COPY rootfs/common/ rootfs/php/ rootfs/frankenphp/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=1 \
    PHP_SESSION_COOKIE_HTTPONLY= \
    PHP_SESSION_USE_STRICT_MODE=0 \
    PHP_SESSION_COOKIE_SAMESITE=
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

FROM php:${PHP_VERSION}-fpm-trixie AS php-fpm
ARG PKG_STAMP
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-fpm /out/ /
# hadolint ignore=DL3008,SC2086
RUN --mount=type=bind,from=ext-builder-fpm,source=/runtime-deps,target=/tmp/runtime-deps \
    apt-get update \
    && apt-get upgrade -y \
    && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps \
    && xargs apt-mark manual < /tmp/runtime-deps \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS \
    && xargs dpkg -s < /tmp/runtime-deps > /dev/null \
    && rm -rf /var/lib/apt/lists/* \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && rm /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/www.conf.default \
    && find / -xdev -perm /6000 -type f -exec chmod ug-s {} +
COPY rootfs/common/ rootfs/php/ rootfs/php-fpm/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=1 \
    PHP_SESSION_COOKIE_HTTPONLY= \
    PHP_SESSION_USE_STRICT_MODE=0 \
    PHP_SESSION_COOKIE_SAMESITE= \
    PHP_FPM_PM=dynamic \
    PHP_FPM_MAX_CHILDREN=10 \
    PHP_FPM_START_SERVERS=2 \
    PHP_FPM_MIN_SPARE_SERVERS=1 \
    PHP_FPM_MAX_SPARE_SERVERS=3 \
    PHP_FPM_MAX_REQUESTS=500 \
    PHP_FPM_REQUEST_TERMINATE_TIMEOUT=60
WORKDIR /app
EXPOSE 9000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php-fpm", "-R"]

FROM php-fpm AS php-fpm-nginx
ARG NGINX_VERSION
ADD --chmod=644 --checksum=sha256:55385da31d198fa6a5012d40ae98ecb272a6c4e8fffffba94719ffd3e87de37a https://nginx.org/keys/nginx_signing.key /usr/share/keyrings/nginx.asc
# hadolint ignore=DL3008
RUN echo 'deb [signed-by=/usr/share/keyrings/nginx.asc] http://nginx.org/packages/debian trixie nginx' > /etc/apt/sources.list.d/nginx.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "nginx=${NGINX_VERSION}-*" gettext-base \
    && rm /etc/nginx/conf.d/default.conf \
    && rm -rf /var/lib/apt/lists/*
COPY --from=s6 /s6/ /
COPY rootfs/nginx/ rootfs/s6/ /
ENV PHP_FPM_HOST=127.0.0.1 \
    PHP_FPM_PORT=9000 \
    PHP_FPM_STATUS_ALLOW="127.0.0.1 ::1" \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1
STOPSIGNAL SIGTERM
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh", "/init"]
CMD []

FROM debian:trixie-slim AS nginx
ARG PKG_STAMP
ARG NGINX_VERSION
ADD --chmod=644 --checksum=sha256:55385da31d198fa6a5012d40ae98ecb272a6c4e8fffffba94719ffd3e87de37a https://nginx.org/keys/nginx_signing.key /usr/share/keyrings/nginx.asc
# hadolint ignore=DL3008
RUN echo 'deb [signed-by=/usr/share/keyrings/nginx.asc] http://nginx.org/packages/debian trixie nginx' > /etc/apt/sources.list.d/nginx.list \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends "nginx=${NGINX_VERSION}-*" gettext-base \
    && rm /etc/nginx/conf.d/default.conf \
    && rm -rf /var/lib/apt/lists/* \
    && find / -xdev -perm /6000 -type f -exec chmod ug-s {} +
COPY rootfs/common/ rootfs/nginx/ /
ENV APP_ROOT=/app \
    PHP_FPM_HOST=php-fpm \
    PHP_FPM_PORT=9000 \
    PHP_FPM_STATUS_ALLOW="127.0.0.1 ::1" \
    PHP_POST_MAX_SIZE=32M
WORKDIR /app
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["nginx", "-e", "stderr", "-g", "daemon off;"]
