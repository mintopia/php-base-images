#!/bin/sh
# Builds FrankenPHP against the ZTS libphp in /usr/local, following upstream's Dockerfile.
set -eux

ldflags=
if command -v apk >/dev/null; then
	apk add --no-cache brotli-dev cmake libcap
	ldflags="-extldflags '-Wl,-z,stack-size=0x80000'"
else
	apt-get update
	apt-get install -y --no-install-recommends cmake libbrotli-dev libcap2-bin
	rm -rf /var/lib/apt/lists/*
fi

mkdir -p /usr/src/watcher /usr/src/frankenphp
curl -fsSL "https://github.com/e-dant/watcher/archive/refs/tags/$WATCHER_VERSION.tar.gz" | tar xz -C /usr/src/watcher --strip-components 1
cmake -S /usr/src/watcher -B /usr/src/watcher/build -DCMAKE_BUILD_TYPE=Release -DBUILD_BIN=OFF
cmake --build /usr/src/watcher/build -j "$(nproc)"
cmake --install /usr/src/watcher/build
ldconfig /usr/local/lib 2>/dev/null || true

curl -fsSL "https://github.com/php/frankenphp/archive/refs/tags/v$FRANKENPHP_SRC_VERSION.tar.gz" | tar xz -C /usr/src/frankenphp --strip-components 1
cd /usr/src/frankenphp/caddy/frankenphp
export CGO_CFLAGS="-DFRANKENPHP_VERSION=$FRANKENPHP_SRC_VERSION $PHP_CFLAGS" \
	CGO_CPPFLAGS="$PHP_CPPFLAGS" \
	CGO_LDFLAGS="-L/usr/local/lib -lssl -lcrypto -lreadline -largon2 -lcurl -lonig -lz $PHP_LDFLAGS"
GOBIN=/usr/local/bin ../../go.sh install -buildvcs=false -ldflags "-w -s $ldflags \
	-X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP v$FRANKENPHP_SRC_VERSION PHP $PHP_VERSION Caddy' \
	-X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' \
	-X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy'"
setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp
frankenphp version
frankenphp build-info
