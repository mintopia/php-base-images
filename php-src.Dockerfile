# syntax=docker/dockerfile:1
# PHP built from a php-src git tag; zts/fpm/frankenphp targets are drop-in replacements for
# php:<ver>-zts-<os> / php:<ver>-fpm-<os> / dunglas/frankenphp:<ver>-php<ver>-<os>.
ARG PHP_TAG
ARG OS=alpine
ARG ALPINE_VERSION=3
ARG GO_VERSION=1.27

FROM --platform=$BUILDPLATFORM debian:trixie-slim AS src
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates wget autoconf bison re2c make xz-utils bzip2 gzip \
    && rm -rf /var/lib/apt/lists/*
ARG PHP_TAG
WORKDIR /work
RUN test -n "$PHP_TAG" \
    && git clone --quiet --depth 1 --branch "$PHP_TAG" https://github.com/php/php-src.git php-src \
    && bash php-src/scripts/dev/makedist "$PHP_TAG" \
    && mv php-src/php-*.tar.xz /php.tar.xz

FROM alpine:${ALPINE_VERSION} AS os-alpine
ENV PHPIZE_DEPS="autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c"
# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates curl openssl tar xz \
    && adduser -u 82 -D -S -G www-data www-data

FROM debian:trixie-slim AS os-trixie
ENV PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c"
# hadolint ignore=DL3008,SC2086
RUN printf 'Package: php*\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/no-debian-php \
    && apt-get update \
    && apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3006
FROM os-${OS} AS php-base
ARG PHP_TAG
ENV PHP_INI_DIR=/usr/local/etc/php \
    PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_CPPFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_LDFLAGS="-Wl,-O1 -pie" \
    PHP_VERSION=${PHP_TAG#php-}
RUN mkdir -p "$PHP_INI_DIR/conf.d" /var/www/html \
    && chown www-data:www-data /var/www/html \
    && chmod 1777 /var/www/html
COPY build/docker-php/docker-php-* /usr/local/bin/
COPY --from=src /php.tar.xz /usr/src/php.tar.xz

FROM php-base AS builder-alpine
# hadolint ignore=DL3018,SC2086
RUN apk add --no-cache $PHPIZE_DEPS coreutils linux-headers \
        argon2-dev curl-dev gnu-libiconv-dev libsodium-dev libxml2-dev oniguruma-dev openssl-dev readline-dev sqlite-dev \
        freetype-dev libjpeg-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev net-snmp-dev \
    && rm -f /usr/include/iconv.h

FROM php-base AS builder-trixie
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev \
        libfreetype-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev libsnmp-dev \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3006
FROM builder-${OS} AS build-zts
RUN --mount=type=bind,source=build/php-src.sh,target=/php-src.sh \
    VARIANT=zts /php-src.sh

# hadolint ignore=DL3006
FROM builder-${OS} AS build-fpm
RUN --mount=type=bind,source=build/php-src.sh,target=/php-src.sh \
    VARIANT=fpm /php-src.sh

FROM php-base AS zts
COPY --from=build-zts /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=build-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php --version
CMD ["php", "-a"]

FROM php-base AS fpm
COPY --from=build-fpm /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=build-fpm,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php --version && php-fpm -t
WORKDIR /var/www/html
STOPSIGNAL SIGQUIT
EXPOSE 9000
CMD ["php-fpm"]

FROM golang:${GO_VERSION}-${OS} AS golang

FROM build-zts AS build-frankenphp
ARG FRANKENPHP_SRC_VERSION
ARG WATCHER_VERSION
COPY --from=golang /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:$PATH \
    GOTOOLCHAIN=local
RUN --mount=type=bind,source=build/frankenphp-src.sh,target=/frankenphp-src.sh \
    /frankenphp-src.sh

FROM zts AS frankenphp
COPY --from=build-frankenphp /usr/local/lib/libwatcher* /usr/local/lib/
COPY --from=build-frankenphp /usr/local/bin/frankenphp /usr/local/bin/
# hadolint ignore=DL3008,DL3018
RUN if command -v apk >/dev/null; then apk add --no-cache brotli-libs libcap libstdc++ mailcap; \
    else apt-get update && apt-get install -y --no-install-recommends libbrotli1 libcap2-bin libstdc++6 mailcap && rm -rf /var/lib/apt/lists/* && ldconfig; fi \
    && mkdir -p /app/public /config/caddy /data/caddy /etc/caddy /etc/frankenphp \
    && frankenphp version
ENV XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data \
    GODEBUG=cgocheck=0
WORKDIR /app
EXPOSE 80 443 443/udp 2019
HEALTHCHECK CMD ["curl", "-f", "http://localhost:2019/metrics"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]
