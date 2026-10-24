#!/bin/sh
# Builds PHP from /usr/src/php.tar.xz into /usr/local like docker-library/php, writes runtime deps to /runtime-deps.
# One ZTS build with CLI, embed (FrankenPHP) and FPM; the zts, fpm and frankenphp images copy it.
set -eux

id=$(echo "$PHP_VERSION" | awk -F. '{ print $1 * 100 + $2 }')

set -- --enable-zts --disable-zend-signals --enable-zend-max-execution-timers \
	--disable-cgi --disable-phpdbg --enable-embed \
	--enable-fpm --with-fpm-user=www-data --with-fpm-group=www-data \
	--enable-mbstring
if [ "$id" -lt 806 ]; then
	set -- "$@" --with-pic --with-pear
fi

docker-php-source extract
cd /usr/src/php
# GH-18743: x86_64 TLS asm rejected by newer binutils; fixed upstream from 8.3
sed -i 's/: "=a" (ti));/: "=D" (ti));/' ext/opcache/jit/zend_jit_x86.dasc 2>/dev/null || true

gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
if command -v apk >/dev/null; then
	set -- "$@" --with-iconv=/usr
else
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"
	[ -d /usr/include/curl ] || ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl
	set -- "$@" --with-iconv --with-libdir="lib/$debMultiarch"
fi

export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS" \
	PHP_BUILD_PROVIDER='https://github.com/mintopia/php-base-images' PHP_UNAME='Linux - Docker'
./configure \
	--build="$gnuArch" \
	--sysconfdir="${PHP_INI_DIR%/php}" \
	--with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
	--enable-option-checking=fatal \
	--with-mhash \
	--enable-mysqlnd \
	--with-password-argon2 \
	--with-sodium=shared \
	--with-pdo-sqlite=/usr \
	--with-sqlite3=/usr \
	--with-curl \
	--with-openssl \
	--with-readline \
	--with-zlib \
	--enable-bcmath=shared \
	--enable-pcntl=shared \
	--enable-gd=shared --with-freetype --with-jpeg --with-webp \
	--with-pdo-mysql=shared,mysqlnd \
	--with-pdo-pgsql=shared \
	--with-pdo-odbc=shared,unixODBC,/usr \
	--with-snmp=shared \
	--enable-intl=shared \
	--with-zip=shared \
	--enable-exif=shared \
	--enable-sockets=shared \
	--with-gmp=shared \
	--enable-soap=shared \
	"$@"
make -j "$(nproc)"
find . -type f -name '*.a' -delete
make install
find /usr/local -type f -perm /0111 -exec strip --strip-all {} + 2>/dev/null || true
cp php.ini-* "$PHP_INI_DIR/"
cd /
docker-php-source delete

if [ "$id" -lt 806 ]; then
	pecl update-channels
	rm -rf /tmp/pear ~/.pearrc
fi
if [ "$id" -lt 805 ]; then
	docker-php-ext-enable opcache
fi
docker-php-ext-enable sodium bcmath pcntl gd pdo_mysql pdo_pgsql pdo_odbc snmp intl zip exif sockets gmp soap

cd /usr/local/etc
cp php-fpm.conf.default php-fpm.conf
cp php-fpm.d/www.conf.default php-fpm.d/www.conf
sed -ri 's/^(listen = 127.0.0.1:9000)/;\1/' php-fpm.d/www.conf
grep -q '^;listen = 127.0.0.1:9000' php-fpm.d/www.conf
printf '[global]\nerror_log = /proc/self/fd/2\nlog_limit = 8192\n\n[www]\naccess.log = /proc/self/fd/2\nclear_env = no\ncatch_workers_output = yes\ndecorate_workers_output = no\nlisten = 9000\n' > php-fpm.d/docker.conf
printf '[global]\ndaemonize = no\n' > php-fpm.d/zz-docker.conf
echo 'fastcgi.logging = Off' > "$PHP_INI_DIR/conf.d/docker-fpm.ini"
cd /

php -m
if command -v apk >/dev/null; then
	scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
		| tr ',' '\n' | sort -u \
		| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' > /runtime-deps
	# icu-libs only pulls English locale data; intl needs every locale
	echo icu-data-full >> /runtime-deps
else
	find /usr/local -type f \( -perm -u+x -o -name '*.so' \) -exec ldd {} + 2>/dev/null \
		| awk '$3 ~ /^\// && $3 !~ /^\/usr\/local\// { print $3 }' | sort -u \
		| xargs -r readlink -f | xargs -r dpkg-query -S \
		| cut -d: -f1 | sort -u > /runtime-deps
fi
cat /runtime-deps
