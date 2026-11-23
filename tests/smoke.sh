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
	docker rmi -f "$id-app" >/dev/null 2>&1 || true
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
echo '<?php sleep(4); echo "done";' > "$work/public/slow.php"
# shellcheck disable=SC2016
echo '<?php echo $_SERVER["REMOTE_ADDR"];' > "$work/public/addr.php"
# shellcheck disable=SC2016
echo '<?php echo implode("|", array_map(fn ($k) => $_SERVER[$k] ?? "", ["REMOTE_ADDR", "HTTPS", "HTTP_X_FORWARDED_FOR", "HTTP_X_FORWARDED_PROTO", "HTTP_X_FORWARDED_HOST", "HTTP_FORWARDED"]));' > "$work/public/fwd.php"
# shellcheck disable=SC2016
echo '<?php echo implode(" ", array_keys(array_filter($_SERVER, fn ($v, $k) => $v === "" && str_starts_with($k, "HTTP_"), ARRAY_FILTER_USE_BOTH)));' > "$work/public/empty.php"
make_laravel_app() {
	mkdir -p "$work/laravel/public" "$work/laravel/storage/logs" "$work/laravel/bootstrap" "$work/laravel/vendor/laravel/octane/bin"
	cat > "$work/laravel/artisan" <<'PHP'
<?php
if (($argv[1] ?? '') !== 'optimize') exit(1);
file_put_contents(__DIR__ . '/bootstrap/cache/config.php', '<?php return [];');
PHP
	cat > "$work/laravel/vendor/laravel/octane/bin/frankenphp-worker.php" <<'PHP'
<?php
$n = 0;
while (frankenphp_handle_request(function () use (&$n) {
    echo 'octane ', ++$n, ' ', $_SERVER['APP_BASE_PATH'] ?? '', ' ', $_SERVER['HTTPS'] ?? '';
}));
PHP
	echo static > "$work/laravel/public/static.txt"
	touch "$work/laravel/storage/logs/old.log"
}
make_laravel_app
spoof=(-H 'X-Forwarded-For: 6.6.6.6, 203.0.113.7' -H 'X-Forwarded-Proto: https' -H 'X-Forwarded-Host: evil.example' -H 'Forwarded: for=6.6.6.6')
chmod -R a+rX "$work"
docker network create "$id" >/dev/null

check_php() {
	docker run --rm -v "$root/versions.json:/versions.json:ro" --entrypoint php "$image" -d display_startup_errors=1 -r '
		$v = json_decode(file_get_contents("/versions.json"), true)["variable"]["VERSIONS"]["default"][PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION];
		$missing = array_filter($v["extensions"], fn ($e) => !extension_loaded($e === "opcache" ? "Zend OPcache" : $e));
		if ($missing) { fwrite(STDERR, "missing: " . implode(" ", $missing) . PHP_EOL); exit(1); }
		if (extension_loaded("intl") && (new NumberFormatter("de_DE", NumberFormatter::DECIMAL))->format(1234.5) !== "1.234,5") { fwrite(STDERR, "intl has no de_DE locale data" . PHP_EOL); exit(1); }
		if (extension_loaded("mongodb") && !str_contains(shell_exec("php --ri mongodb") ?? "", "libmongoc SSL => enabled")) { fwrite(STDERR, "mongodb built without TLS" . PHP_EOL); exit(1); }
		foreach (["grpc", "redis", "apcu", "mongodb", "opentelemetry", "protobuf"] as $e) { if (extension_loaded($e)) echo "$e=", phpversion($e), PHP_EOL; }
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

bake_root_owned_laravel_app() {
	printf 'FROM %s\nCOPY . /app\n' "$image" | docker build -q -t "$id-app" -f - "$work/laravel" >/dev/null
}

wait_log() {
	for _ in $(seq 30); do
		docker logs "$id" 2>&1 | grep -q "$1" && return 0
		sleep 1
	done
	fail "log never showed '$1'"
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
		docker run --rm "${hardened[@]}" --tmpfs /tmp "$image" sh -c 'touch "$HOME/.probe"' || fail "HOME not writable under --read-only as PUID"
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
		bake_root_owned_laravel_app
		owners=$(docker run --rm -e LARAVEL_OPTIMIZE=true -e PUID=1000 "$id-app" \
			sh -c 'echo $(stat -c %u bootstrap/cache/config.php storage/logs/old.log storage/framework/views) $(id -u)')
		[ "$owners" = "1000 1000 1000 1000" ] || fail "LARAVEL_OPTIMIZE as PUID gave owners '$owners'"
		[ "$(docker run --rm -e LARAVEL_OPTIMIZE=true "$id-app" stat -c %u bootstrap/cache/config.php)" = 0 ] || fail "LARAVEL_OPTIMIZE without PUID"
		err=$(docker run --rm "${hardened[@]}" -e LARAVEL_OPTIMIZE=true "$id-app" true 2>&1) && fail "LARAVEL_OPTIMIZE ran with root-owned storage on a read-only root"
		[[ "$err" == *"cannot chown"* ]] || fail "LARAVEL_OPTIMIZE failure unclear: $err"
		docker run --rm "${hardened[@]}" -e LARAVEL_OPTIMIZE=true --tmpfs /app/storage:uid=1000,gid=1000 --tmpfs /app/bootstrap/cache:uid=1000,gid=1000 \
			"$id-app" test -f bootstrap/cache/config.php || fail "LARAVEL_OPTIMIZE with tmpfs storage under --read-only"
		docker run --rm -e LARAVEL_OPTIMIZE=true "$image" true 2>/dev/null || fail "LARAVEL_OPTIMIZE without artisan"
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
		[ "$(docker run --rm -e PUID=1000 "$image" sh -c 'echo "$(id -u) $$"')" = "1000 1" ] || fail "changed command not run alone as PUID"
		curl -fsS -o "$work/slow.out" "http://127.0.0.1:$port/slow.php" &
		slow=$!
		sleep 1
		docker stop -t 15 "$id" >/dev/null
		wait "$slow" && [ "$(cat "$work/slow.out")" = "done" ] || fail "docker stop cut off an in-flight request"
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
		empty=$(curl -fsS "${spoof[@]}" "http://127.0.0.1:$port/empty.php")
		[ -z "$empty" ] || fail "empty headers reached PHP: $empty"
		docker rm -f "$id" >/dev/null
		octane=(-e LARAVEL_OCTANE=true -v "$work/laravel:/app:ro")
		! docker run --rm "${octane[@]}" -e FRANKENPHP_CONFIG='worker /app/public/index.php' "$image" true 2>/dev/null || fail "LARAVEL_OCTANE accepted a second worker"
		docker run -d --name "$id" -p 127.0.0.1::8080 --cpus 2 "${hardened[@]}" --tmpfs /data --tmpfs /config --tmpfs /tmp \
			-e TRUSTED_PROXIES='127.0.0.1/32 ::1/128' "${octane[@]}" "$image" >/dev/null
		port=$(docker port "$id" 8080/tcp | head -1 | cut -d: -f2)
		wait_log '"worker_threads":2,'
		body=$(curl -fsS "http://127.0.0.1:$port/some/route")
		[[ "$body" == "octane "[0-9]*" /app " ]] || fail "LARAVEL_OCTANE request returned '$body'"
		[ "$(curl -fsS "http://127.0.0.1:$port/static.txt")" = static ] || fail "LARAVEL_OCTANE static file"
		body=$(docker exec "$id" curl -fsS -H 'X-Forwarded-Proto: https' http://127.0.0.1:8080/)
		[[ "$body" == *" on" ]] || fail "LARAVEL_OCTANE behind a trusted proxy returned '$body'"
		docker rm -f "$id" >/dev/null
		docker run -d --name "$id" "${octane[@]}" -e LARAVEL_OCTANE_WORKERS=3 "$image" >/dev/null
		wait_log '"worker_threads":3,'
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
