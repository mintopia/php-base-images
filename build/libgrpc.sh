#!/bin/sh
# gRPC core and its bundled deps as static PIC archives in /opt/grpc, with the matching PHP extension source (ADR 0030).
# OpenSSL and zlib come from the OS, so its updates and CVE scans cover them.
set -eux

if command -v apk >/dev/null; then
	apk add --no-cache cmake g++ git linux-headers make openssl-dev zlib-dev
else
	apt-get update
	apt-get install -y --no-install-recommends ca-certificates cmake g++ git libssl-dev make zlib1g-dev
fi

. /build/git-auth.sh
git clone --quiet --depth 1 -b "v$GRPC_VERSION" https://github.com/grpc/grpc /src/grpc
git -C /src/grpc submodule update --quiet --init --depth 1 \
	third_party/abseil-cpp third_party/cares/cares third_party/grpc-proto third_party/protobuf third_party/re2

cmake -S /src/grpc -B /src/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
	-DgRPC_BUILD_TESTS=OFF -DgRPC_SSL_PROVIDER=package -DgRPC_ZLIB_PROVIDER=package
# core only: the PHP extension links nothing from grpc++ or protobuf; about 1.5 GB per compile job
jobs=$(awk -v n="$(nproc)" '/^MemAvailable:/ { j = int($2 / 1500000); print (j < 1 ? 1 : j < n ? j : n) }' /proc/meminfo)
cmake --build /src/build --target grpc -j "$jobs"

mkdir -p /opt/grpc/lib
cp -a /src/grpc/include /opt/grpc/
find /src/build -name '*.a' -exec cp {} /opt/grpc/lib/ \;
strip --strip-debug /opt/grpc/lib/*.a
cp -a /src/grpc/src/php/ext/grpc /opt/grpc/php-ext
