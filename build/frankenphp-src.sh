#!/bin/sh
# Builds FrankenPHP against the ZTS libphp in /usr/local, following upstream's Dockerfile.
set -eux

ldflags=
if command -v apk >/dev/null; then
	apk add --no-cache brotli-dev
	ldflags="-extldflags '-Wl,-z,stack-size=0x80000'"
else
	apt-get update
	apt-get install -y --no-install-recommends libbrotli-dev
	rm -rf /var/lib/apt/lists/*
fi
ldconfig /usr/local/lib 2>/dev/null || true

cd /usr/src/frankenphp/caddy/frankenphp
export CGO_CFLAGS="-DFRANKENPHP_VERSION=$FRANKENPHP_SRC_VERSION $PHP_CFLAGS" \
	CGO_CPPFLAGS="$PHP_CPPFLAGS" \
	CGO_LDFLAGS="-L/usr/local/lib -lssl -lcrypto -lreadline -largon2 -lcurl -lonig -lz $PHP_LDFLAGS"
GOBIN=/usr/local/bin ../../go.sh install -buildvcs=false -ldflags "-w -s $ldflags \
	-X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP v$FRANKENPHP_SRC_VERSION PHP $PHP_VERSION Caddy' \
	-X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' \
	-X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy'"
frankenphp version
frankenphp build-info
