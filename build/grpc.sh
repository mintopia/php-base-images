#!/bin/sh
# Links grpc.so statically against the libgrpc product; hiding the archives' symbols keeps its upb and abseil from clashing with protobuf's
set -eux

# one -Wl, so libtool neither drops the archives as non-libtool deps nor moves the system libs ahead of them
libs="-Wl,--exclude-libs,ALL,--start-group,$(echo /opt/grpc/lib/*.a | tr ' ' ','),--end-group,-lssl,-lcrypto,-lz,-lstdc++,-lm,-lpthread,-ldl,-lrt"
cd /opt/grpc/php-ext
phpize
./configure --enable-grpc=/opt/grpc LIBS="$libs"
make -j"$(nproc)" GRPC_SHARED_LIBADD="$libs"
make install
docker-php-ext-enable grpc
