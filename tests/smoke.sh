#!/usr/bin/env bash
set -euo pipefail

image=$1
target=$2
sidecar=${3:-${image%-nginx}-php-fpm}
root=$(cd "$(dirname "$0")/.." && pwd)
id=smoke-$$
work=$(mktemp -d)

cleanup() {
	docker rm -f "$id" "$id-fpm" >/dev/null 2>&1 || true
	docker network rm "$id" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT

fail() {
	echo "FAIL [$target]: $*" >&2
	if docker container inspect "$id" >/dev/null 2>&1; then docker logs "$id" 2>&1 | tail -20 >&2; fi
	exit 1
}

mkdir -p "$work/public"
echo '<?php echo "PHP ", PHP_VERSION;' > "$work/public/index.php"
# shellcheck disable=SC2016
echo '<?php echo $_SERVER["REMOTE_ADDR"];' > "$work/public/addr.php"
# shellcheck disable=SC2016
echo '<?php echo implode("|", array_map(fn ($k) => $_SERVER[$k] ?? "", ["REMOTE_ADDR", "HTTPS", "HTTP_X_FORWARDED_FOR", "HTTP_X_FORWARDED_PROTO", "HTTP_X_FORWARDED_HOST", "HTTP_FORWARDED"]));' > "$work/public/fwd.php"
# shellcheck disable=SC2016
echo '<?php echo implode(" ", array_keys(array_filter($_SERVER, fn ($v, $k) => $v === "" && str_starts_with($k, "HTTP_"), ARRAY_FILTER_USE_BOTH)));' > "$work/public/empty.php"
spoof=(-H 'X-Forwarded-For: 6.6.6.6, 203.0.113.7' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: evil.example' -H 'Forwarded: for=6.6.6.6')
chmod -R a+rX "$work"
docker network create "$id" >/dev/null

check_php() {
	docker run --rm -v "$root/versions.json:/versions.json:ro" --entrypoint php "$image" -d display_startup_errors=1 -r '
		$v = json_decode(file_get_contents("/versions.json"), true)["variable"]["VERSIONS"]["default"][PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION];
		$missing = array_filter($v["extensions"], fn ($e) => !extension_loaded($e === "opcache" ? "Zend OPcache" : $e));
		if ($missing) { fwrite(STDERR, "missing: " . implode(" ", $missing) . PHP_EOL); exit(1); }
		foreach (["grpc", "redis", "opentelemetry", "protobuf"] as $e) { if (extension_loaded($e)) echo "$e=", phpversion($e), PHP_EOL; }
	' > "$work/versions" 2> "$work/stderr" || fail "$(cat "$work/stderr")"
	[ ! -s "$work/stderr" ] || fail "startup output: $(cat "$work/stderr")"
	while IFS='=' read -r ext version; do
		label=$(docker inspect --format "{{ index .Config.Labels \"net.mintopia.ext.$ext.version\" }}" "$image")
		[[ -n "$label" && "$version" == *"$label" ]] || fail "label $ext=$label, loaded $version"
	done < "$work/versions"
}

start() {
	local public=$1
	shift
	docker run -d --name "$id" --network "$id" -p 127.0.0.1::8080 -v "$work/public:$public:ro" "$@" >/dev/null
	port=$(docker port "$id" 8080/tcp | head -1 | cut -d: -f2)
}

http_ok() {
	local body
	for _ in $(seq 30); do
		body=$(curl -fsS "http://127.0.0.1:$port/" 2>/dev/null) && break
		sleep 1
	done
	[[ "${body:-}" == "PHP 8."* ]] || fail "GET / returned '${body:-}'"
}

# read-only root plus the documented tmpfs mounts, as PUID with only the caps PUID needs
hardened=(--read-only --cap-drop ALL --cap-add SETUID --cap-add SETGID -e PUID=1000)

status_code() {
	curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$1"
}

case "$target" in
	cli)
		check_php
		[ "$(docker run --rm "$image" id -u)" = 0 ] || fail "default user not root"
		[ "$(docker run --rm -e PUID=1000 -e PGID=1001 "$image" id -u):$(docker run --rm -e PUID=1000 -e PGID=1001 "$image" id -g)" = 1000:1001 ] \
			|| fail "PUID/PGID not applied"
		[ "$(docker run --rm "$image" pwd):$(docker run --rm -e APP_ROOT=/tmp "$image" pwd)" = /app:/tmp ] || fail "APP_ROOT not the working directory"
		[ "$(docker run --rm "${hardened[@]}" -e PGID=1001 "$image" sh -c 'echo $(id -u):$(id -g)')" = 1000:1001 ] || fail "PUID under --read-only --cap-drop ALL"
		[ "$(docker run --rm "$image" php -r 'echo ini_get("display_errors");'):$(docker run --rm -e PHP_INI_MODE=development "$image" php -r 'echo ini_get("display_errors");')" = ":1" ] \
			|| fail "PHP_INI_MODE not applied"
		! docker run --rm -e PHP_INI_MODE=bogus "$image" true 2>/dev/null || fail "invalid PHP_INI_MODE accepted"
		[ "$(docker run --rm "$image" php -r 'echo ini_get("expose_php") ?: "off";')" = off ] || fail "expose_php on"
		mkdir "$work/hooks"
		# shellcheck disable=SC2016
		for h in 10-a 20-b; do
			printf '#!/bin/sh\nexport HOOKS="${HOOKS:-}%s:$(id -u) "\nexec "$@"\n' "$h" > "$work/hooks/$h"
		done
		chmod +x "$work/hooks/"*
		out=$(docker run --rm -e PUID=1000 -v "$work/hooks:/docker-entrypoint.d:ro" "$image" sh -c 'echo "$HOOKS$(id -u)"')
		[ "$out" = "10-a:0 20-b:0 1000" ] || fail "entrypoint hooks returned '$out'"
		;;
	php-fpm)
		check_php
		docker run -d --name "$id" -e PHP_FPM_STATUS_PATH=/status -v "$work/public:/app/public:ro" "$image" >/dev/null
		docker exec -e DEBIAN_FRONTEND=noninteractive "$id" sh -c 'apk add --no-cache -q fcgi 2>/dev/null || { apt-get update -qq && apt-get install -y -qq libfcgi-bin; }' >/dev/null
		for _ in $(seq 30); do
			out=$(docker exec -e SCRIPT_NAME=/index.php -e SCRIPT_FILENAME=/app/public/index.php -e REQUEST_METHOD=GET "$id" \
				cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null) && break
			sleep 1
		done
		[[ "${out:-}" == *"PHP 8."* && "${out:-}" != *"Status:"* ]] || fail "fastcgi returned '${out:-}'"
		out=$(docker exec -e SCRIPT_NAME=/status -e SCRIPT_FILENAME=/status -e REQUEST_METHOD=GET "$id" cgi-fcgi -bind -connect 127.0.0.1:9000)
		[[ "$out" == *"pool:"* ]] || fail "status page returned '$out'"
		docker rm -f "$id" >/dev/null
		docker run -d -t --name "$id" "${hardened[@]}" --tmpfs /run --tmpfs /tmp "$image" >/dev/null
		sleep 3
		docker logs "$id" 2>&1 | grep -q 'ready to handle connections' || fail "not ready under --read-only"
		;;
	php-fpm-nginx)
		check_php
		start /srv/public -e APP_ROOT=/srv "${hardened[@]}" --tmpfs /run:exec --tmpfs /tmp -e PHP_FPM_STATUS_PATH=/status -e NGINX_STATUS_PATH=/nginx_status "$image"
		http_ok
		! curl -sI "http://127.0.0.1:$port/" | grep -qi '^x-powered-by' || fail "X-Powered-By sent"
		! docker logs "$id" 2>&1 | grep -q "\"GET /index.php\" 200" || fail "php-fpm access log duplicates nginx"
		docker exec -u 1000 "$id" nginx -e stderr -s reload || fail "nginx -s reload"
		[ "$(status_code /.env)" = 403 ] || fail "dotfile not denied"
		[ "$(status_code /.well-known-secrets)" = 403 ] || fail ".well-known prefix not denied"
		[ "$(status_code /status)" = 403 ] || fail "status not restricted"
		docker exec "$id" curl -fsS http://127.0.0.1:8080/status | grep -q '^pool:' || fail "status not served locally"
		[ "$(status_code /nginx_status)" = 403 ] || fail "nginx status not restricted"
		docker exec "$id" curl -fsS http://127.0.0.1:8080/nginx_status | grep -q '^Active connections' || fail "nginx status not served locally"
		addr=$(docker exec "$id" curl -fsS http://127.0.0.1:8080/addr.php)
		[ "$addr" = 127.0.0.1 ] || fail "IPv4 client seen as '$addr'"
		addr=$(docker exec "$id" curl -fsS -H 'X-Forwarded-For: 203.0.113.7' http://127.0.0.1:8080/addr.php)
		[ "$addr" = 127.0.0.1 ] || fail "untrusted X-Forwarded-For honoured: '$addr'"
		fwd=$(docker exec "$id" curl -fsS "${spoof[@]}" http://127.0.0.1:8080/fwd.php)
		[ "$fwd" = "127.0.0.1||127.0.0.1|http||" ] || fail "untrusted forwarded headers reached PHP: '$fwd'"
		workers=$(docker exec "$id" sh -c 'for p in /proc/[0-9]*; do [ "$p" != /proc/$$ ] && grep -qaE "php-fpm: pool|nginx: worker" "$p/cmdline" 2>/dev/null && stat -c %u "$p"; done; true' | sort -u)
		[ "$workers" = 1000 ] || fail "workers run as '$workers'"
		;;
	frankenphp)
		check_php
		docker run --rm --cap-drop ALL "$image" frankenphp version >/dev/null || fail "frankenphp under --cap-drop ALL"
		start /app/public "${hardened[@]}" --tmpfs /data --tmpfs /config --tmpfs /tmp -e TRUSTED_PROXIES='127.0.0.1/32 ::1/128' "$image"
		http_ok
		fwd=$(curl -fsS "${spoof[@]}" "http://127.0.0.1:$port/fwd.php")
		[[ "$fwd" != 203.0.113.7* && "$fwd" == *"||"*"|http||" ]] || fail "untrusted forwarded headers reached PHP: '$fwd'"
		fwd=$(docker exec "$id" curl -fsS "${spoof[@]}" http://127.0.0.1:8080/fwd.php)
		[ "$fwd" = "203.0.113.7|on|203.0.113.7|https|evil.example|" ] || fail "trusted proxy headers seen as '$fwd'"
		;;
	nginx)
		docker run -d --name "$id-fpm" --network "$id" --network-alias php-fpm -v "$work/public:/app/public:ro" "$sidecar" >/dev/null
		start /app/public -e TRUSTED_PROXIES='0.0.0.0/0 ::/0' "${hardened[@]}" --tmpfs /run "$image"
		docker exec -u 1000 "$id" nginx -e stderr -t 2>&1 | grep -q 'test is successful' || fail "nginx -t"
		docker exec -u 1000 "$id" nginx -e stderr -s reload || fail "nginx -s reload"
		http_ok
		addr=$(curl -fsS -H 'X-Forwarded-For: 203.0.113.7' "http://127.0.0.1:$port/addr.php")
		[ "$addr" = 203.0.113.7 ] || fail "trusted X-Forwarded-For seen as '$addr'"
		fwd=$(curl -fsS -H 'X-Forwarded-For: 203.0.113.7' -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$port/fwd.php")
		[ "$fwd" = "203.0.113.7|on|203.0.113.7|https||" ] || fail "trusted proxy headers seen as '$fwd'"
		empty=$(curl -fsS "http://127.0.0.1:$port/empty.php")
		[ -z "$empty" ] || fail "empty headers reached PHP: $empty"
		;;
	*)
		fail "unknown target"
		;;
esac
echo "PASS [$target] $image"
