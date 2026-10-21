#!/bin/sh
# Builds PHP from /usr/src/php.tar.xz into /usr/local, writes runtime deps to /runtime-deps.
# VARIANT=zts -> ZTS CLI (embed for FrankenPHP); VARIANT=nts -> NTS CLI + FPM.
set -eux

mkdir -p /usr/src/php
tar -xJf /usr/src/php.tar.xz -C /usr/src/php --strip-components=1
cd /usr/src/php

case "$VARIANT" in
	zts) variant_flags="--enable-zts --enable-embed --disable-cgi" ;;
	nts) variant_flags="--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data --disable-cgi" ;;
	*) exit 1 ;;
esac

# shellcheck disable=SC2086
./configure \
	--build="$(gcc -dumpmachine)" \
	--with-config-file-path=/usr/local/etc/php \
	--with-config-file-scan-dir=/usr/local/etc/php/conf.d \
	--enable-option-checking=fatal \
	--with-mhash --with-pic \
	--enable-mbstring --enable-mysqlnd \
	--with-password-argon2 --with-sodium=shared \
	--with-pdo-sqlite=/usr --with-sqlite3=/usr \
	--with-curl --with-iconv --with-openssl --with-readline --with-zlib \
	--disable-phpdbg \
	--enable-bcmath=shared --enable-pcntl=shared \
	--enable-gd=shared --with-freetype --with-jpeg --with-webp \
	--with-pdo-mysql=shared,mysqlnd --with-pdo-pgsql=shared \
	--with-pdo-odbc=shared,unixODBC,/usr --with-snmp=shared \
	$variant_flags

make -j"$(nproc)"
make install
find /usr/local -type f -perm -u+x -exec strip --strip-all {} + 2>/dev/null || true
make clean
mkdir -p /usr/local/etc/php/conf.d
cp php.ini-* /usr/local/etc/php/
cd /
rm -rf /usr/src/php

# match upstream php:*-fpm layout so existing Dockerfiles apply unchanged
if [ "$VARIANT" = nts ]; then
	cd /usr/local/etc
	sed 's!=NONE/!=!g' php-fpm.conf.default > php-fpm.conf
	cp php-fpm.d/www.conf.default php-fpm.d/www.conf
	printf '[global]\nerror_log = /proc/self/fd/2\nlog_limit = 8192\n[www]\naccess.log = /proc/self/fd/2\nclear_env = no\ncatch_workers_output = yes\ndecorate_workers_output = no\n' > php-fpm.d/docker.conf
	printf '[global]\ndaemonize = no\n[www]\nlisten = 9000\n' > php-fpm.d/zz-docker.conf
	cd /
fi

for ext in sodium bcmath pcntl gd pdo_mysql pdo_pgsql pdo_odbc snmp opcache; do
	[ -f "$(php-config --extension-dir)/$ext.so" ] || continue
	kind=extension; [ "$ext" = opcache ] && kind=zend_extension
	echo "$kind=$ext" > "/usr/local/etc/php/conf.d/docker-php-ext-$ext.ini"
done

php -m
if command -v apk >/dev/null; then
	scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
		| tr ',' '\n' | sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' > /runtime-deps
else
	find /usr/local -type f \( -perm -u+x -o -name '*.so' \) -exec ldd {} + 2>/dev/null \
		| awk '$3 ~ /^\// && $3 !~ /^\/usr\/local\// { print $3 }' | sort -u \
		| xargs -r readlink -f | xargs -r dpkg-query -S \
		| cut -d: -f1 | sort -u > /runtime-deps
fi
cat /runtime-deps
