#!/bin/sh
# One step per Dockerfile stage: deps | bundled | grpc | pie <extension> <package>.
# Steps after deps write only their new files to /out/files and their runtime deps to /out/deps/<step>.
# shellcheck disable=SC2086
set -eux

ext_dir="$(php-config --extension-dir)"
conf_dir="$PHP_INI_DIR/conf.d"

if [ "$1" = deps ]; then
	if command -v apk >/dev/null; then
		apk add --no-cache --virtual .build-deps $PHPIZE_DEPS git openssl-dev zlib-dev
	else
		# php-src images ship no compiler, and install-php-extensions expects one
		apt-get update
		apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates git libssl-dev libtool libwebp-dev unzip zlib1g-dev
	fi
	ls "$ext_dir" > /ext-before
	ls "$conf_dir" > /conf-before
	exit 0
fi

want() { case " $EXTENSIONS " in *" $1 "*) ;; *) return 1 ;; esac; }

step=$1
case "$step" in
	bundled)
		bundled=
		for ext in $EXTENSIONS; do
			case "$ext" in grpc|redis|apcu|mongodb|opentelemetry|protobuf) ;; *) bundled="$bundled $ext" ;; esac
		done
		install-php-extensions $bundled
		;;
	grpc)
		if want grpc; then /build/grpc.sh; fi
		;;
	pie)
		step=$2
		if want "$2"; then pie install "$3"; fi
		;;
esac

files=/out/files
mkdir -p "$files$ext_dir" "$files$conf_dir" /out/deps
for f in "$ext_dir"/*; do
	grep -qxF "${f##*/}" /ext-before && continue
	strip --strip-unneeded "$f"
	cp -a "$f" "$files$ext_dir/"
done
for f in "$conf_dir"/*; do
	grep -qxF "${f##*/}" /conf-before || cp -a "$f" "$files$conf_dir/"
done

deps="/out/deps/$step"
if command -v apk >/dev/null; then
	scanelf --needed --nobanner --format '%n#p' --recursive "$files$ext_dir" \
		| tr ',' '\n' | sort -u \
		| awk 'NF && system("[ -e /usr/local/lib/" $1 " ]") != 0 { print "so:" $1 }' > "$deps"
	# icu-libs only pulls English locale data; intl needs every locale
	if [ "$step" = bundled ] && want intl; then echo icu-data-full >> "$deps"; fi
else
	if [ "$step" = bundled ]; then mkdir -p "$files/var/lib/snmp/cert_indexes"; fi
	if find "$files$ext_dir" -name '*.so' -exec ldd {} + | grep 'not found'; then exit 1; fi
	find "$files$ext_dir" -name '*.so' -exec ldd {} + \
		| awk '$3 ~ /^\// && $3 !~ /^\/usr\/local\// { print $3 }' | sort -u \
		| xargs -r readlink -f | xargs -r dpkg-query -S \
		| cut -d: -f1 | sort -u > "$deps"
fi
cat "$deps"
