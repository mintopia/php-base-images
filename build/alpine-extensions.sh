#!/bin/sh
# shellcheck disable=SC2086
set -eux

bundled=
pie=
grpc=
redis=
redis_opts=
for ext in $EXTENSIONS; do
	case "$ext" in
		grpc) grpc=1 ;;
		redis) redis=1 ;;
		apcu) pie="$pie apcu/apcu:$APCU_VERSION" ;;
		# PECL marks 3.2.17RC1 as its stable release, the only one on Packagist
		igbinary) pie="$pie igbinary/igbinary:$IGBINARY_VERSION" redis_opts=--enable-redis-igbinary ;;
		opentelemetry) pie="$pie open-telemetry/ext-opentelemetry:$OPENTELEMETRY_VERSION" ;;
		protobuf) pie="$pie pie-extensions/protobuf:$PROTOBUF_VERSION" ;;
		*) bundled="$bundled $ext" ;;
	esac
done

apk add --no-cache --virtual .build-deps $PHPIZE_DEPS git grpc-dev
install-php-extensions $bundled

for package in $pie; do
	pie install "$package"
done
# after igbinary, whose headers the redis serializer builds against
if [ -n "$redis" ]; then
	pie install "phpredis/phpredis:$REDIS_VERSION" $redis_opts
fi

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
# icu-libs only pulls English locale data; intl needs every locale
case " $EXTENSIONS " in *" intl "*) echo icu-data-full >> /runtime-deps ;; esac
