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
	docker run -d --name "$id" --network "$id" -p 127.0.0.1::8080 -v "$work/public:/app/public:ro" "$@" >/dev/null
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

status_code() {
	curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$1"
}

case "$target" in
	cli)
		check_php
		[ "$(docker run --rm "$image" id -u)" = 0 ] || fail "default user not root"
		[ "$(docker run --rm -e PUID=1000 -e PGID=1001 "$image" id -u):$(docker run --rm -e PUID=1000 -e PGID=1001 "$image" id -g)" = 1000:1001 ] \
			|| fail "PUID/PGID not applied"
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
		;;
	php-fpm-nginx)
		check_php
		start -e PUID=1000 -e PHP_FPM_STATUS_PATH=/status "$image"
		http_ok
		[ "$(status_code /status)" = 403 ] || fail "status not restricted"
		docker exec "$id" curl -fsS http://127.0.0.1:8080/status | grep -q '^pool:' || fail "status not served locally"
		workers=$(docker exec "$id" sh -c 'for p in /proc/[0-9]*; do [ "$p" != /proc/$$ ] && grep -qaE "php-fpm: pool|nginx: worker" "$p/cmdline" 2>/dev/null && stat -c %u "$p"; done' | sort -u)
		[ "$workers" = 1000 ] || fail "workers run as '$workers'"
		;;
	frankenphp)
		check_php
		start -e PUID=1000 "$image"
		http_ok
		;;
	nginx)
		docker run -d --name "$id-fpm" --network "$id" --network-alias php-fpm -v "$work/public:/app/public:ro" "$sidecar" >/dev/null
		start "$image"
		docker exec "$id" nginx -t 2>&1 | grep -q 'test is successful' || fail "nginx -t"
		http_ok
		;;
	*)
		fail "unknown target"
		;;
esac
echo "PASS [$target] $image"
