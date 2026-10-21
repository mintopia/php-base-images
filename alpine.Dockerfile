# syntax=docker/dockerfile:1
ARG PHP_VERSION=8.5
ARG FRANKENPHP_VERSION=1
ARG INSTALLER_VERSION=2.12.3
ARG ALPINE_VERSION=3

FROM mlocati/php-extension-installer:${INSTALLER_VERSION} AS installer
FROM ghcr.io/php/pie:bin AS pie

FROM php:${PHP_VERSION}-zts-alpine AS ext-builder-zts
ARG EXTENSIONS
ARG REDIS_VERSION
ARG OPENTELEMETRY_VERSION
ARG PROTOBUF_VERSION
ARG GRPC_VERSION
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=bind,from=installer,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    /build/alpine-extensions.sh

FROM php:${PHP_VERSION}-fpm-alpine AS ext-builder-nts
ARG EXTENSIONS
ARG REDIS_VERSION
ARG OPENTELEMETRY_VERSION
ARG PROTOBUF_VERSION
ARG GRPC_VERSION
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=bind,from=installer,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    --mount=type=bind,from=pie,source=/pie,target=/usr/local/bin/pie \
    /build/alpine-extensions.sh

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

FROM php:${PHP_VERSION}-zts-alpine AS cli
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-zts /out/ /
# hadolint ignore=DL3018
RUN --mount=type=bind,from=ext-builder-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    xargs apk add --no-cache setpriv < /tmp/runtime-deps \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY rootfs/common/ rootfs/php/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30
WORKDIR /app
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["php", "-a"]

FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}-alpine AS frankenphp
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-zts /out/ /
# hadolint ignore=DL3018
RUN --mount=type=bind,from=ext-builder-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    xargs apk add --no-cache setpriv < /tmp/runtime-deps \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && chmod 1777 /data/caddy /config/caddy
COPY rootfs/common/ rootfs/php/ rootfs/frankenphp/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

FROM php:${PHP_VERSION}-fpm-alpine AS php-fpm
COPY --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=pie /pie /usr/local/bin/pie
COPY --from=ext-builder-nts /out/ /
# hadolint ignore=DL3018
RUN --mount=type=bind,from=ext-builder-nts,source=/runtime-deps,target=/tmp/runtime-deps \
    xargs apk add --no-cache setpriv < /tmp/runtime-deps \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && rm /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/www.conf.default
COPY rootfs/common/ rootfs/php/ rootfs/php-fpm/ /
ENV APP_ROOT=/app \
    PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=32M \
    PHP_POST_MAX_SIZE=32M \
    PHP_MAX_EXECUTION_TIME=30 \
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
ADD https://nginx.org/keys/nginx_signing.rsa.pub /etc/apk/keys/
# hadolint ignore=DL3018
RUN printf '@nginx https://nginx.org/packages/alpine/v%s/main\n' "$(cut -d. -f1,2 /etc/alpine-release)" >> /etc/apk/repositories \
    && apk add --no-cache "nginx@nginx~${NGINX_VERSION}" gettext-envsubst
COPY --from=s6 /s6/ /
COPY rootfs/nginx/ rootfs/s6/ /
ENV PHP_FPM_HOST=127.0.0.1 \
    PHP_FPM_PORT=9000 \
    PHP_FPM_STATUS_ALLOW="127.0.0.1 ::1" \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_KEEP_ENV=1
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh", "/init"]
CMD []

FROM alpine:${ALPINE_VERSION} AS nginx
ARG NGINX_VERSION
ADD https://nginx.org/keys/nginx_signing.rsa.pub /etc/apk/keys/
# hadolint ignore=DL3018
RUN printf '@nginx https://nginx.org/packages/alpine/v%s/main\n' "$(cut -d. -f1,2 /etc/alpine-release)" >> /etc/apk/repositories \
    && apk add --no-cache "nginx@nginx~${NGINX_VERSION}" gettext-envsubst setpriv
COPY rootfs/common/ rootfs/nginx/ /
ENV APP_ROOT=/app \
    PHP_FPM_HOST=php-fpm \
    PHP_FPM_PORT=9000 \
    PHP_FPM_STATUS_ALLOW="127.0.0.1 ::1" \
    PHP_POST_MAX_SIZE=32M
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
