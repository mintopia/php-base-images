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
		mongodb) pie="$pie mongodb/mongodb-extension:$MONGODB_VERSION" ;;
		opentelemetry) pie="$pie open-telemetry/ext-opentelemetry:$OPENTELEMETRY_VERSION" ;;
		protobuf) pie="$pie pie-extensions/protobuf:$PROTOBUF_VERSION" ;;
		*) bundled="$bundled $ext" ;;
	esac
done

# php-src images ship no compiler, and install-php-extensions expects one
apt-get update
apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates git libgrpc-dev libssl-dev libtool libwebp-dev unzip
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
mkdir -p "/out$ext_dir" /out/usr/local/etc/php /out/var/lib/snmp/cert_indexes
cp -a "$ext_dir/." "/out$ext_dir/"
cp -a "$PHP_INI_DIR/conf.d" /out/usr/local/etc/php/
if find "$ext_dir" -name '*.so' -exec ldd {} + | grep 'not found'; then exit 1; fi
find "$ext_dir" -name '*.so' -exec ldd {} + \
	| awk '$3 ~ /^\// && $3 !~ /^\/usr\/local\// { print $3 }' | sort -u \
	| xargs -r readlink -f | xargs -r dpkg-query -S \
	| cut -d: -f1 | sort -u > /runtime-deps
