#!/bin/sh
# shellcheck disable=SC2086
set -eux

bundled=
pie=
grpc=
for ext in $EXTENSIONS; do
	case "$ext" in
		grpc) grpc=1 ;;
		redis) pie="$pie phpredis/phpredis:$REDIS_VERSION" ;;
		opentelemetry) pie="$pie open-telemetry/ext-opentelemetry:$OPENTELEMETRY_VERSION" ;;
		protobuf) pie="$pie pie-extensions/protobuf:$PROTOBUF_VERSION" ;;
		*) bundled="$bundled $ext" ;;
	esac
done

install-php-extensions $bundled

apk add --no-cache --virtual .build-deps $PHPIZE_DEPS git grpc-dev
for package in $pie; do
	pie install "$package"
done

if [ -n "$grpc" ]; then
	/build/grpc.sh
fi

ext_dir="$(php-config --extension-dir)"
mkdir -p "/out$ext_dir" /out/usr/local/etc/php
cp -a "$ext_dir/." "/out$ext_dir/"
cp -a "$PHP_INI_DIR/conf.d" /out/usr/local/etc/php/
scanelf --needed --nobanner --format '%n#p' --recursive "$ext_dir" \
	| tr ',' '\n' | sort -u \
	| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' > /runtime-deps
