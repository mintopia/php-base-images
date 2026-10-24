# syntax=docker/dockerfile:1
# PHP, FrankenPHP and PIE extensions built from source, and the zts/fpm/frankenphp bases the OS Dockerfiles build on.
# Product stages (php, frankenphp, ext-*) are FROM scratch and hold only their files; a bake context can replace each (ADR 0023).
ARG PHP_TAG
ARG OS=alpine
ARG ALPINE_VERSION=3
ARG GO_VERSION=1.27
ARG INSTALLER_VERSION=2.12.3
ARG PIE_VERSION=1.5.3

FROM mlocati/php-extension-installer:${INSTALLER_VERSION} AS installer-upstream

FROM --platform=$BUILDPLATFORM alpine:3 AS installer
COPY --from=installer-upstream /usr/bin/install-php-extensions /usr/bin/
# shortcut: installer rejects unreleased PHP minors; drop once it lists 8.6
RUN sed -i 's/| 805)/| 805 | 806)/' /usr/bin/install-php-extensions \
    && grep -q '| 806)' /usr/bin/install-php-extensions

FROM ghcr.io/php/pie:${PIE_VERSION}-bin AS pie

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
# hadolint ignore=DL3008
RUN printf 'Package: php*\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/no-debian-php \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3006
FROM os-${OS} AS php-base
ENV PHP_INI_DIR=/usr/local/etc/php \
    PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_CPPFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_LDFLAGS="-Wl,-O1 -pie"
RUN mkdir -p "$PHP_INI_DIR/conf.d" /var/www/html \
    && chown www-data:www-data /var/www/html \
    && chmod 1777 /var/www/html
COPY build/docker-php/docker-php-* /usr/local/bin/

FROM php-base AS builder-alpine
# hadolint ignore=DL3018,SC2086
RUN apk add --no-cache $PHPIZE_DEPS coreutils linux-headers \
        argon2-dev curl-dev gnu-libiconv-dev libsodium-dev libxml2-dev oniguruma-dev openssl-dev readline-dev sqlite-dev \
        freetype-dev libjpeg-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev net-snmp-dev \
        icu-dev libzip-dev gmp-dev \
    && rm -f /usr/include/iconv.h

FROM php-base AS builder-trixie
# hadolint ignore=DL3008,SC2086
RUN apt-get update \
    && apt-get install -y --no-install-recommends $PHPIZE_DEPS \
        libargon2-dev libcurl4-openssl-dev libonig-dev libreadline-dev libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev \
        libfreetype-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libpq-dev unixodbc-dev libsnmp-dev \
        libicu-dev libzip-dev libgmp-dev \
    && rm -rf /var/lib/apt/lists/*

# tag and source come after the builder deps so a PHP patch bump reuses them
# hadolint ignore=DL3006
FROM builder-${OS} AS build-php
ARG PHP_TAG
ENV PHP_VERSION=${PHP_TAG#php-}
COPY --link --from=src /php.tar.xz /usr/src/php.tar.xz
RUN --mount=type=bind,source=build/php-src.sh,target=/php-src.sh \
    /php-src.sh

# one build serves zts, fpm and frankenphp
FROM scratch AS php
COPY --from=build-php /usr/local/ /usr/local/
COPY --from=build-php /usr/src/php.tar.xz /usr/src/
COPY --from=build-php /runtime-deps /

# libphp.so (embed) only ships in frankenphp
FROM php-base AS fpm-files
COPY --from=php /usr/local/ /usr/local/
RUN rm -rf /usr/local/lib/libphp.so /usr/local/php/man

FROM fpm-files AS zts-files
RUN rm -rf /usr/local/sbin/php-fpm /usr/local/etc/php-fpm* /usr/local/php/fpm "$PHP_INI_DIR/conf.d/docker-fpm.ini"

FROM php-base AS php-tagged
ARG PHP_TAG
ENV PHP_VERSION=${PHP_TAG#php-}
COPY --link --from=php /usr/src/php.tar.xz /usr/src/php.tar.xz
COPY --link --from=installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --link --from=pie /pie /usr/local/bin/pie

FROM php-tagged AS zts
COPY --from=zts-files /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=php,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php --version
CMD ["php", "-a"]

FROM php-tagged AS fpm
COPY --from=fpm-files /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN --mount=type=bind,from=php,source=/runtime-deps,target=/tmp/runtime-deps \
    if command -v apk >/dev/null; then xargs apk add --no-cache < /tmp/runtime-deps; \
    else apt-get update && xargs apt-get install -y --no-install-recommends < /tmp/runtime-deps && rm -rf /var/lib/apt/lists/*; fi \
    && php --version && php-fpm -t
WORKDIR /var/www/html
STOPSIGNAL SIGQUIT
EXPOSE 9000
CMD ["php-fpm"]

# builder with the PHP install, for builds that link against it
# hadolint ignore=DL3006
FROM builder-${OS} AS php-dev
COPY --from=php /usr/local/ /usr/local/

# independent of PHP so a PHP tag bump reuses it from cache
# hadolint ignore=DL3006
FROM os-${OS} AS watcher
ARG WATCHER_VERSION
ARG WATCHER_SHA256
ADD --checksum=sha256:${WATCHER_SHA256} https://github.com/e-dant/watcher/archive/refs/tags/${WATCHER_VERSION}.tar.gz /tmp/watcher.tar.gz
# hadolint ignore=DL3008,DL3018
RUN if command -v apk >/dev/null; then apk add --no-cache cmake g++ linux-headers make; \
    else apt-get update && apt-get install -y --no-install-recommends cmake g++ make && rm -rf /var/lib/apt/lists/*; fi \
    && mkdir /src && tar -xzf /tmp/watcher.tar.gz -C /src --strip-components 1 \
    && cmake -S /src -B /src/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_BIN=OFF \
    && cmake --build /src/build -j "$(nproc)" \
    && cmake --install /src/build --prefix /out

FROM golang:${GO_VERSION}-${OS} AS golang

FROM golang AS frankenphp-src
ARG FRANKENPHP_SRC_VERSION
ARG FRANKENPHP_SRC_SHA256
ADD --checksum=sha256:${FRANKENPHP_SRC_SHA256} https://github.com/php/frankenphp/archive/refs/tags/v${FRANKENPHP_SRC_VERSION}.tar.gz /tmp/frankenphp.tar.gz
WORKDIR /usr/src/frankenphp
RUN tar -xzf /tmp/frankenphp.tar.gz --strip-components 1 \
    && go -C caddy mod download

FROM php-dev AS build-frankenphp
ARG PHP_TAG
ARG FRANKENPHP_SRC_VERSION
COPY --from=golang /usr/local/go /usr/local/go
COPY --from=frankenphp-src /go/pkg/mod /root/go/pkg/mod
COPY --from=frankenphp-src /usr/src/frankenphp /usr/src/frankenphp
COPY --from=watcher /out/ /usr/local/
ENV PATH=/usr/local/go/bin:$PATH \
    GOTOOLCHAIN=local \
    GOPROXY=off \
    PHP_VERSION=${PHP_TAG#php-}
RUN --mount=type=bind,source=build/frankenphp-src.sh,target=/frankenphp-src.sh \
    /frankenphp-src.sh

FROM scratch AS frankenphp
COPY --from=build-frankenphp /usr/local/lib/libwatcher*.so* /usr/local/lib/
COPY --from=build-frankenphp /usr/local/bin/frankenphp /usr/local/bin/

FROM zts AS zts-frankenphp
COPY --from=php /usr/local/lib/libphp.so /usr/local/lib/
COPY --from=frankenphp /usr/local/ /usr/local/
# hadolint ignore=DL3008,DL3018
RUN if command -v apk >/dev/null; then apk add --no-cache brotli-libs libstdc++ mailcap; \
    else apt-get update && apt-get install -y --no-install-recommends libbrotli1 libstdc++6 mailcap && rm -rf /var/lib/apt/lists/* && ldconfig; fi \
    && mkdir -p /app/public /config/caddy /data/caddy /etc/caddy /etc/frankenphp \
    && frankenphp version
ENV XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data \
    GODEBUG=cgocheck=0
WORKDIR /app
EXPOSE 80 443 443/udp 2019
HEALTHCHECK CMD ["curl", "-f", "http://localhost:2019/metrics"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

# one stage per extension so a version bump rebuilds only that extension, and they build in parallel
FROM zts AS ext-base
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh deps

# cheap (the php-src build already has these), so not a cached product
FROM ext-base AS ext-bundled
ARG EXTENSIONS
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh bundled

FROM ext-base AS build-ext-grpc
ARG EXTENSIONS
ARG GRPC_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh grpc

FROM ext-base AS build-ext-redis
ARG EXTENSIONS
ARG REDIS_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh pie redis "phpredis/phpredis:$REDIS_VERSION"

FROM ext-base AS build-ext-apcu
ARG EXTENSIONS
ARG APCU_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh pie apcu "apcu/apcu:$APCU_VERSION"

FROM ext-base AS build-ext-mongodb
ARG EXTENSIONS
ARG MONGODB_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh pie mongodb "mongodb/mongodb-extension:$MONGODB_VERSION"

FROM ext-base AS build-ext-opentelemetry
ARG EXTENSIONS
ARG OPENTELEMETRY_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh pie opentelemetry "open-telemetry/ext-opentelemetry:$OPENTELEMETRY_VERSION"

FROM ext-base AS build-ext-protobuf
ARG EXTENSIONS
ARG PROTOBUF_VERSION
RUN --mount=type=bind,source=build,target=/build \
    /build/extensions.sh pie protobuf "pie-extensions/protobuf:$PROTOBUF_VERSION"

FROM scratch AS ext-grpc
COPY --from=build-ext-grpc /out/ /

FROM scratch AS ext-redis
COPY --from=build-ext-redis /out/ /

FROM scratch AS ext-apcu
COPY --from=build-ext-apcu /out/ /

FROM scratch AS ext-mongodb
COPY --from=build-ext-mongodb /out/ /

FROM scratch AS ext-opentelemetry
COPY --from=build-ext-opentelemetry /out/ /

FROM scratch AS ext-protobuf
COPY --from=build-ext-protobuf /out/ /

# products are file trees, so ext copies them whole
# hadolint global ignore=DL3067
FROM scratch AS ext
COPY --link --from=ext-bundled /out/ /
COPY --link --from=ext-grpc / /
COPY --link --from=ext-redis / /
COPY --link --from=ext-apcu / /
COPY --link --from=ext-mongodb / /
COPY --link --from=ext-opentelemetry / /
COPY --link --from=ext-protobuf / /
