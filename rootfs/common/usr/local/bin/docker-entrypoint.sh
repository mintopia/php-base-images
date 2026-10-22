#!/bin/sh
set -e

export APP_ROOT="${APP_ROOT:-/app}"
export APP_PUBLIC_PATH="${APP_PUBLIC_PATH:-$APP_ROOT/public}"
if [ -d "$APP_ROOT" ]; then
	cd "$APP_ROOT"
fi

case "${PHP_INI_MODE:=production}" in
	production) ;;
	development) export PHPRC="${PHP_INI_DIR:-}/php.ini-development" ;;
	*) echo "PHP_INI_MODE must be production or development, got '$PHP_INI_MODE'" >&2; exit 1 ;;
esac

# php-fpm's master stays root and drops pools to these numeric ids; everything else runs via run-as
export PHP_FPM_USER="${PUID:-root}" PHP_FPM_GROUP="${PGID:-${PUID:-root}}"
NGINX_USER_DIRECTIVE='user root;'
if [ -n "${PUID:-}" ]; then
	NGINX_USER_DIRECTIVE=
	# stdio is root-owned 0600; PUID processes reopen /dev/stdout by path (nginx does). chmod, not chown: root keeps access without DAC_OVERRIDE
	chmod a+w /proc/self/fd/1 /proc/self/fd/2 2>/dev/null || true
fi

if [ -f /proc/net/if_inet6 ]; then
	PHP_FPM_LISTEN='[::]:9000'
	NGINX_LISTEN='listen 8080; listen [::]:8080 ipv6only=on;'
else
	PHP_FPM_LISTEN='0.0.0.0:9000'
	NGINX_LISTEN='listen 8080;'
fi
export PHP_FPM_LISTEN NGINX_LISTEN

# NGINX_REAL_IP_* are the older names
export TRUSTED_PROXIES="${TRUSTED_PROXIES:-${NGINX_REAL_IP_FROM:-}}"
export CLIENT_IP_HEADER="${CLIENT_IP_HEADER:-${NGINX_REAL_IP_HEADER:-X-Forwarded-For}}"
# whole block or nothing: Caddy rejects a second servers block, e.g. one from CADDY_GLOBAL_OPTIONS
CADDY_SERVERS=
[ -z "$TRUSTED_PROXIES" ] || CADDY_SERVERS="servers {
trusted_proxies static $TRUSTED_PROXIES
client_ip_headers $CLIENT_IP_HEADER
trusted_proxies_strict
}"
export CADDY_SERVERS

if [ -d /usr/local/etc/php-fpm.d ]; then
	mkdir -p /run/php-fpm
	{
		echo '[www]'
		[ -z "${PHP_FPM_STATUS_PATH:-}" ] || echo "pm.status_path = $PHP_FPM_STATUS_PATH"
		[ -z "${PHP_FPM_PING_PATH:-}" ] || echo "ping.path = $PHP_FPM_PING_PATH"
	} > /run/php-fpm/status.conf
fi

if [ -d /etc/nginx/templates ]; then
	allow=
	for cidr in ${PHP_FPM_STATUS_ALLOW:-}; do
		allow="${allow}allow ${cidr}; "
	done
	NGINX_STATUS_LOCATIONS=
	for path in ${PHP_FPM_STATUS_PATH:-} ${PHP_FPM_PING_PATH:-}; do
		NGINX_STATUS_LOCATIONS="${NGINX_STATUS_LOCATIONS}location = ${path} { ${allow}deny all; include /etc/nginx/fastcgi_params; fastcgi_param SCRIPT_FILENAME ${path}; fastcgi_pass \$php_fpm; }
"
	done
	if [ -n "${NGINX_STATUS_PATH:-}" ]; then
		NGINX_STATUS_LOCATIONS="${NGINX_STATUS_LOCATIONS}location = ${NGINX_STATUS_PATH} { ${allow}deny all; stub_status; }
"
	fi
	# realip resolves REMOTE_ADDR; $trusted_proxy gates which forwarded headers reach PHP
	NGINX_REAL_IP=
	NGINX_TRUSTED_GEO=
	for cidr in $TRUSTED_PROXIES; do
		NGINX_REAL_IP="${NGINX_REAL_IP}set_real_ip_from ${cidr}; "
		NGINX_TRUSTED_GEO="${NGINX_TRUSTED_GEO}${cidr} 1; "
	done
	if [ -n "$NGINX_REAL_IP" ]; then
		NGINX_REAL_IP="${NGINX_REAL_IP}real_ip_header ${CLIENT_IP_HEADER}; real_ip_recursive on;"
	fi
	# re-resolve PHP_FPM_HOST so a restarted php-fpm container's new IP is picked up
	NGINX_RESOLVER=$(awk '$1 == "nameserver" && $2 !~ /%/ { printf "%s ", ($2 ~ /:/ ? "[" $2 "]" : $2) }' /etc/resolv.conf)
	if [ -n "$NGINX_RESOLVER" ]; then
		[ -f /proc/net/if_inet6 ] || NGINX_RESOLVER="${NGINX_RESOLVER}ipv6=off "
		NGINX_RESOLVER="resolver ${NGINX_RESOLVER}valid=10s;"
	fi
	export NGINX_STATUS_LOCATIONS NGINX_REAL_IP NGINX_TRUSTED_GEO NGINX_RESOLVER NGINX_USER_DIRECTIVE
	# rendered under /run so /etc can be read-only; config stays root-owned, only var/ (pid, temp) is writable by PUID
	mkdir -p /run/nginx/var && chmod 1777 /run/nginx/var
	find /etc/nginx/templates -name '*.template' | while read -r template; do
		target="/run/nginx/${template#/etc/nginx/templates/}"
		mkdir -p "$(dirname "$target")"
		# shellcheck disable=SC2016
		envsubst '${NGINX_LISTEN} ${APP_PUBLIC_PATH} ${NGINX_USER_DIRECTIVE} ${PHP_FPM_HOST} ${PHP_FPM_PORT} ${PHP_POST_MAX_SIZE} ${NGINX_STATUS_LOCATIONS} ${NGINX_REAL_IP} ${NGINX_TRUSTED_GEO} ${NGINX_RESOLVER}' \
			< "$template" > "${target%.template}"
	done
fi

case "$1" in
	php-fpm | /init) ;;
	*) set -- run-as "$@" ;;
esac

# chained entrypoints: run as root in name order, each must end with exec "$@"
# ponytail: word-split, so hook filenames can't contain whitespace
hooks=
for hook in /docker-entrypoint.d/*; do
	if [ -f "$hook" ] && [ -x "$hook" ]; then
		hooks="$hook $hooks"
	fi
done
for hook in $hooks; do
	set -- "$hook" "$@"
done
exec "$@"
