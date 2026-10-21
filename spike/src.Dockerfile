# syntax=docker/dockerfile:1
# Spike: PHP built from a php-src git tag onto plain alpine / trixie-slim.
# docker buildx build -f spike/src.Dockerfile --build-arg PHP_TAG=php-8.5.11 --build-arg OS=alpine --target zts .
ARG PHP_TAG=php-8.5.11
ARG OS=alpine
ARG ALPINE_VERSION=3
ARG UPSTREAM_SCRIPTS=php:8.5-cli-alpine

# Arch-independent: git tag -> release-equivalent tarball (generated configure, parsers, lexers).
FROM --platform=$BUILDPLATFORM debian:trixie-slim AS src
# hadolint ignore=DL3008,SC2086
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates wget autoconf bison re2c make xz-utils bzip2 gzip \
    && rm -rf /var/lib/apt/lists/*
ARG PHP_TAG
WORKDIR /work
RUN git clone --quiet --depth 1 --branch "$PHP_TAG" https://github.com/php/php-src.git php-src \
    && bash php-src/scripts/dev/makedist "$PHP_TAG" \
    && mv php-src/php-*.tar.xz /php.tar.xz

FROM ${UPSTREAM_SCRIPTS} AS upstream-scripts

FROM alpine:${ALPINE_VERSION} AS builder-alpine
# hadolint ignore=DL3018
RUN apk add --no-cache build-base linux-headers pkgconf file xz tar \
        argon2-dev curl-dev libsodium-dev openssl-dev readline-dev sqlite-dev zlib-dev oniguruma-dev libxml2-dev \
        freetype-dev libjpeg-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev net-snmp-dev \
    && adduser -u 82 -D -S -G www-data www-data

FROM debian:trixie-slim AS builder-trixie
# hadolint ignore=DL3008,SC2086
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential pkg-config file xz-utils \
        libargon2-dev libcurl4-openssl-dev libsodium-dev libssl-dev libreadline-dev libsqlite3-dev zlib1g-dev libonig-dev libxml2-dev \
        libfreetype-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev libsnmp-dev \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3006
FROM builder-${OS} AS build-zts
RUN --mount=type=bind,from=src,source=/php.tar.xz,target=/usr/src/php.tar.xz \
    --mount=type=bind,source=spike/build-php.sh,target=/build-php.sh \
    VARIANT=zts sh /build-php.sh

# hadolint ignore=DL3006
FROM builder-${OS} AS build-nts
RUN --mount=type=bind,from=src,source=/php.tar.xz,target=/usr/src/php.tar.xz \
    --mount=type=bind,source=spike/build-php.sh,target=/build-php.sh \
    VARIANT=nts sh /build-php.sh

FROM alpine:${ALPINE_VERSION} AS runtime-alpine
ENV PHPIZE_DEPS="autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c"
# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates curl tar xz \
    && adduser -u 82 -D -S -G www-data www-data

FROM debian:trixie-slim AS runtime-trixie
ENV PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c"
# upstream trixie keeps PHPIZE_DEPS; installers and build/trixie-extensions.sh rely on it
# hadolint ignore=DL3008,SC2086
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils $PHPIZE_DEPS \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3006
FROM runtime-${OS} AS php-base
ENV PHP_INI_DIR=/usr/local/etc/php
COPY --from=upstream-scripts /usr/local/bin/docker-php-* /usr/local/bin/
COPY --from=src /php.tar.xz /usr/src/php.tar.xz

FROM php-base AS zts
COPY --from=build-zts /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=build-zts,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php -m
CMD ["php", "-a"]

FROM php-base AS nts
COPY --from=build-nts /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=build-nts,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php -m && php-fpm -t
STOPSIGNAL SIGQUIT
CMD ["php-fpm"]
