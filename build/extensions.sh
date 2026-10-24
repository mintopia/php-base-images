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
		apcu) pie="$pie apcu/apcu:$APCU_VERSION" ;;
		mongodb) pie="$pie mongodb/mongodb-extension:$MONGODB_VERSION" ;;
		opentelemetry) pie="$pie open-telemetry/ext-opentelemetry:$OPENTELEMETRY_VERSION" ;;
		protobuf) pie="$pie pie-extensions/protobuf:$PROTOBUF_VERSION" ;;
		*) bundled="$bundled $ext" ;;
	esac
done

if command -v apk >/dev/null; then
	apk add --no-cache --virtual .build-deps $PHPIZE_DEPS git grpc-dev openssl-dev
else
	# php-src images ship no compiler, and install-php-extensions expects one
	apt-get update
	apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates git libgrpc-dev libssl-dev libtool libwebp-dev unzip
fi
install-php-extensions $bundled

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
if command -v apk >/dev/null; then
	scanelf --needed --nobanner --format '%n#p' --recursive "$ext_dir" \
		| tr ',' '\n' | sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' > /runtime-deps
	# icu-libs only pulls English locale data; intl needs every locale
	case " $EXTENSIONS " in *" intl "*) echo icu-data-full >> /runtime-deps ;; esac
else
	mkdir -p /out/var/lib/snmp/cert_indexes
	if find "$ext_dir" -name '*.so' -exec ldd {} + | grep 'not found'; then exit 1; fi
	find "$ext_dir" -name '*.so' -exec ldd {} + \
		| awk '$3 ~ /^\// && $3 !~ /^\/usr\/local\// { print $3 }' | sort -u \
		| xargs -r readlink -f | xargs -r dpkg-query -S \
		| cut -d: -f1 | sort -u > /runtime-deps
fi
