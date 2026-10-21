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

# shortcut: installer rejects unreleased PHP minors; drop once it lists 8.6
sed 's/| 805)/| 805 | 806)/' "$(command -v install-php-extensions)" > /tmp/install-php-extensions
sh /tmp/install-php-extensions $bundled

apt-get update
apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates git libgrpc-dev libtool libwebp-dev unzip
for package in $pie; do
	pie install "$package"
done

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
