#!/bin/sh
set -eux

if command -v apk >/dev/null; then
	version="$(pkg-config --modversion grpc++)"
else
	version="$(dpkg-query -W -f='${Version}' libgrpc-dev | cut -d- -f1)"
fi
[ "$version" = "$GRPC_VERSION" ]

. /build/git-auth.sh
git clone --depth 1 --filter=blob:none --sparse -b "v$version" https://github.com/grpc/grpc /src/grpc
git -C /src/grpc sparse-checkout set src/php/ext/grpc
cd /src/grpc/src/php/ext/grpc
sed -i 's/zend_exception_get_default(TSRMLS_C)/zend_ce_exception/' call.c
phpize
./configure
make -j"$(nproc)"
make install
docker-php-ext-enable grpc
