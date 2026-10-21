#!/bin/sh
set -e

export APP_ROOT="${APP_ROOT:-/app}"
export APP_PUBLIC_PATH="${APP_PUBLIC_PATH:-$APP_ROOT/public}"
if [ -d "$APP_ROOT" ]; then
	cd "$APP_ROOT"
fi

run_as=root
if [ -n "${PUID:-}" ]; then
	sed -i '/^app:/d' /etc/passwd /etc/group
	echo "app:x:${PGID:-$PUID}:" >> /etc/group
	echo "app:x:${PUID}:${PGID:-$PUID}::${APP_ROOT}:/sbin/nologin" >> /etc/passwd
	run_as=app
fi
export PHP_FPM_USER="$run_as" PHP_FPM_GROUP="$run_as" NGINX_USER="$run_as"

if [ -f /proc/net/if_inet6 ]; then
	PHP_FPM_LISTEN='[::]:9000'
	NGINX_LISTEN='listen 8080; listen [::]:8080 ipv6only=on;'
else
	PHP_FPM_LISTEN='0.0.0.0:9000'
	NGINX_LISTEN='listen 8080;'
fi
export PHP_FPM_LISTEN NGINX_LISTEN

if [ -d /usr/local/etc/php-fpm.d ]; then
	status_conf=/usr/local/etc/php-fpm.d/zz-status.conf
	rm -f "$status_conf"
	if [ -n "${PHP_FPM_STATUS_PATH:-}${PHP_FPM_PING_PATH:-}" ]; then
		echo '[www]' > "$status_conf"
		if [ -n "${PHP_FPM_STATUS_PATH:-}" ]; then
			echo "pm.status_path = $PHP_FPM_STATUS_PATH" >> "$status_conf"
		fi
		if [ -n "${PHP_FPM_PING_PATH:-}" ]; then
			echo "ping.path = $PHP_FPM_PING_PATH" >> "$status_conf"
		fi
	fi
fi

if [ -d /etc/nginx/templates ]; then
	allow=
	for cidr in ${PHP_FPM_STATUS_ALLOW:-}; do
		allow="${allow}allow ${cidr}; "
	done
	NGINX_STATUS_LOCATIONS=
	for path in ${PHP_FPM_STATUS_PATH:-} ${PHP_FPM_PING_PATH:-}; do
		NGINX_STATUS_LOCATIONS="${NGINX_STATUS_LOCATIONS}location = ${path} { ${allow}deny all; include fastcgi_params; fastcgi_param SCRIPT_FILENAME ${path}; fastcgi_pass \$php_fpm; }
"
	done
	if [ -n "${NGINX_STATUS_PATH:-}" ]; then
		NGINX_STATUS_LOCATIONS="${NGINX_STATUS_LOCATIONS}location = ${NGINX_STATUS_PATH} { ${allow}deny all; stub_status; }
"
	fi
	NGINX_REAL_IP=
	for cidr in ${NGINX_REAL_IP_FROM:-}; do
		NGINX_REAL_IP="${NGINX_REAL_IP}set_real_ip_from ${cidr}; "
	done
	if [ -n "$NGINX_REAL_IP" ]; then
		NGINX_REAL_IP="${NGINX_REAL_IP}real_ip_header ${NGINX_REAL_IP_HEADER:-X-Forwarded-For}; real_ip_recursive on;"
	fi
	# re-resolve PHP_FPM_HOST so a restarted php-fpm container's new IP is picked up
	NGINX_RESOLVER=$(awk '$1 == "nameserver" && $2 !~ /%/ { printf "%s ", ($2 ~ /:/ ? "[" $2 "]" : $2) }' /etc/resolv.conf)
	if [ -n "$NGINX_RESOLVER" ]; then
		[ -f /proc/net/if_inet6 ] || NGINX_RESOLVER="${NGINX_RESOLVER}ipv6=off "
		NGINX_RESOLVER="resolver ${NGINX_RESOLVER}valid=10s;"
	fi
	export NGINX_STATUS_LOCATIONS NGINX_REAL_IP NGINX_RESOLVER
	find /etc/nginx/templates -name '*.template' | while read -r template; do
		target="/etc/nginx/${template#/etc/nginx/templates/}"
		# shellcheck disable=SC2016
		envsubst '${NGINX_LISTEN} ${APP_PUBLIC_PATH} ${NGINX_USER} ${PHP_FPM_HOST} ${PHP_FPM_PORT} ${PHP_POST_MAX_SIZE} ${NGINX_STATUS_LOCATIONS} ${NGINX_REAL_IP} ${NGINX_RESOLVER}' \
			< "$template" > "${target%.template}"
	done
fi

case "$1" in
	php-fpm | nginx | /init) ;;
	*) [ "$run_as" = root ] || set -- setpriv --reuid app --regid app --init-groups "$@" ;;
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
