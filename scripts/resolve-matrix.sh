#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 [--all] [--dry-run] [--php VERSION] [--os OS] [--arch ARCH]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
all=false dry_run=false only_php='' only_os='' only_arch=''
while [ $# -gt 0 ]; do
	case $1 in
		--all) all=true ;;
		--dry-run) dry_run=true ;;
		--php) only_php=${2:?}; shift ;;
		--os) only_os=${2:?}; shift ;;
		--arch) only_arch=${2:?}; shift ;;
		*) usage ;;
	esac
	shift
done

log() { echo "$*" >&2; }

# values land in GITHUB_ENV and bake vars; reject anything that could inject
safe() {
	[[ $1 =~ ^[A-Za-z0-9._:+-]+$ ]] || { log "unsafe or empty upstream value: '$1'"; exit 1; }
	printf '%s' "$1"
}

# HEAD only: not counted against Docker Hub anonymous pull limits
digest() {
	local repo=${1%%:*} tag=${1#*:} token auth=()
	[[ $repo == */* ]] || repo=library/$repo
	[ -z "${DOCKERHUB_TOKEN:-}" ] || auth=(-u "$DOCKERHUB_USERNAME:$DOCKERHUB_TOKEN")
	token=$(curl -fsSL --retry 3 "${auth[@]}" "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repo:pull" | jq -r .token)
	safe "$(curl -fsSI --retry 3 -H "Authorization: Bearer $token" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://registry-1.docker.io/v2/$repo/manifests/$tag" | tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" { print $2 }')"
}

apk_version() {
	safe "$(curl -fsSL --retry 3 "$1" | tar -xzO APKINDEX | awk -v p="$2" '/^P:/ { n = substr($0, 3) } /^V:/ && n == p { print substr($0, 3) }' | sed 's/-r[0-9]*$//' | sort -V | tail -1)"
}

deb_version() {
	safe "$(curl -fsSL --retry 3 "$1" | $3 -dc | awk -v p="$2" '$1 == "Package:" { n = $2 } $1 == "Version:" && n == p { print $2 }' | cut -d- -f1 | sort -V | tail -1)"
}

packagist() {
	safe "$(curl -fsSL --retry 3 "https://repo.packagist.org/p2/$1.json" \
		| jq -r --arg p "$1" '.packages[$p][].version | ltrimstr("v") | select(test("^[0-9]+(\\.[0-9]+)*$"))' | sort -V | tail -1)"
}

github_release() {
	local auth=()
	[ -z "${GITHUB_TOKEN:-}" ] || auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
	safe "$(curl -fsSL --retry 3 "${auth[@]}" "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name | ltrimstr("v")')"
}

matrix=$(jq -c '.variable.VERSIONS.default' "$root/versions.json")
mapfile -t keys < <(jq -r 'keys[]' <<<"$matrix" | sort -V)
latest=$(jq -r 'to_entries | map(select(.value.stable) | .key)[]' <<<"$matrix" | sort -V | tail -1)
archs=(amd64 arm64)
[ -z "$only_arch" ] || archs=("$only_arch")

selected=()
for key in "${keys[@]}"; do
	[ -z "$only_php" ] || [ "$key" = "$only_php" ] || continue
	selected+=("$key")
done
[ ${#selected[@]} -gt 0 ] || { log "no PHP version matches '$only_php'"; exit 1; }
nginx_key=$(for key in "${selected[@]}"; do jq -r --arg k "$key" 'select(.[$k].stable) | $k' <<<"$matrix"; done | head -1)

redis=$(packagist phpredis/phpredis)
otel=$(packagist open-telemetry/ext-opentelemetry)
protobuf=$(packagist pie-extensions/protobuf)
s6=$(github_release just-containers/s6-overlay)
common=$(jq -n --arg redis "$redis" --arg otel "$otel" --arg protobuf "$protobuf" --arg s6 "$s6" \
	'{FRANKENPHP_VERSION: "1", REDIS_VERSION: $redis, OPENTELEMETRY_VERSION: $otel, PROTOBUF_VERSION: $protobuf, S6_OVERLAY_VERSION: $s6}')

declare -A os_vars
for os in alpine trixie; do
	[ -z "$only_os" ] || [ "$os" = "$only_os" ] || continue
	case $os in
		alpine)
			base='' nginx='' grpc=''
			;;
		trixie)
			base=$(digest debian:trixie-slim)
			nginx=$(deb_version https://nginx.org/packages/debian/dists/trixie/nginx/binary-amd64/Packages.gz nginx gzip)
			grpc=$(deb_version https://deb.debian.org/debian/dists/trixie/main/binary-amd64/Packages.xz libgrpc-dev xz)
			;;
	esac
	os_vars[$os]=$(jq -c --arg os "$os" --arg base "$base" --arg nginx "$nginx" --arg grpc "$grpc" \
		'. + {OS: $os, NGINX_BASE_DIGEST: $base, NGINX_VERSION: $nginx, GRPC_VERSION: $grpc}' <<<"$common")
done
[ ${#os_vars[@]} -gt 0 ] || { log "no OS matches '$only_os'"; exit 1; }

expected_labels() {
	jq -c -n --arg v "$1" --argjson vars "$2" --argjson exts "$3" '
		{grpc: "GRPC_VERSION", redis: "REDIS_VERSION", opentelemetry: "OPENTELEMETRY_VERSION", protobuf: "PROTOBUF_VERSION"} as $ev
		| {cli: "ZTS_DIGEST", frankenphp: "FRANKENPHP_DIGEST", "php-fpm": "FPM_DIGEST", "php-fpm-nginx": "FPM_DIGEST", nginx: "NGINX_BASE_DIGEST"} as $base
		| {"org.opencontainers.image.base.digest": $vars[$base[$v]]}
		+ (if $v == "nginx" then {} else [$exts[] | select($ev[.]) | {key: "net.mintopia.ext.\(.).version", value: $vars[$ev[.]]}] | from_entries end)
		+ (if $v == "nginx" or $v == "php-fpm-nginx" then {"net.mintopia.nginx.version": $vars.NGINX_VERSION} else {} end)
		+ (if $v == "php-fpm-nginx" then {"net.mintopia.s6.version": $vars.S6_OVERLAY_VERSION} else {} end)'
}

lanes='[]'
merges='[]'
for key in "${selected[@]}"; do
	version=$(jq -c --arg k "$key" '.[$k]' <<<"$matrix")
	tag=$(jq -r .tag <<<"$version")
	exts=$(jq -c .extensions <<<"$version")
	stable=$(jq -r .stable <<<"$version")
	for os in alpine trixie; do
		[ -n "${os_vars[$os]:-}" ] || continue
		jq -e --arg os "$os" '.os | index($os)' <<<"$version" >/dev/null || continue
		targets=(cli php-fpm php-fpm-nginx)
		frankenphp=''
		if [ "$(jq -r .frankenphp <<<"$version")" = true ]; then
			targets+=(frankenphp)
			frankenphp=$(digest "dunglas/frankenphp:1-php$tag-$os")
		fi
		[ "$key" != "$nginx_key" ] || targets+=(nginx)
		zts=$(digest "php:$tag-zts-$os")
		fpm=$(digest "php:$tag-fpm-$os")
		vars=$(jq -c --arg key "$key" --arg zts "$zts" --arg fpm "$fpm" --arg fp "$frankenphp" \
			'. + {PHP_VERSION: $key, ZTS_DIGEST: $zts, FPM_DIGEST: $fpm, FRANKENPHP_DIGEST: $fp}' <<<"${os_vars[$os]}")
		if [ "$os" = alpine ]; then
			# php images can lag alpine:3; grpc.sh asserts the distro grpc version
			minor=$(safe "$(docker run --rm -q "php:$tag-zts-alpine@$zts" cut -d. -f1,2 /etc/alpine-release)")
			grpc=$(apk_version "https://dl-cdn.alpinelinux.org/alpine/v$minor/community/x86_64/APKINDEX.tar.gz" grpc-dev)
			nginx=$(apk_version "https://nginx.org/packages/alpine/v$minor/main/x86_64/APKINDEX.tar.gz" nginx)
			base=$(digest "alpine:$minor")
			vars=$(jq -c --arg grpc "$grpc" --arg nginx "$nginx" --arg alpine "$minor" --arg base "$base" \
				'. + {GRPC_VERSION: $grpc, NGINX_VERSION: $nginx, ALPINE_VERSION: $alpine, NGINX_BASE_DIGEST: $base}' <<<"$vars")
		fi

		stale=()
		if ! $all; then
			for t in "${targets[@]}"; do
				if [ "$t" = nginx ]; then ref=ghcr.io/mintopia/nginx:$os; else ref=ghcr.io/mintopia/php:$key-$os-$t; fi
				if ! published=$(docker buildx imagetools inspect "$ref" --format '{{json .Image}}' 2>/dev/null); then
					stale+=("$t(missing)")
					continue
				fi
				exp=$(expected_labels "$t" "$vars" "$exts")
				for arch in "${archs[@]}"; do
					diff=$(jq -r --arg p "linux/$arch" --argjson exp "$exp" \
						'(.[$p].config.Labels // {}) as $a | [$exp | to_entries[] | select(.value != $a[.key]) | .key] | join(",")' <<<"$published")
					[ -z "$diff" ] || stale+=("$t/$arch($diff)")
				done
			done
			if [ ${#stale[@]} -eq 0 ]; then
				log "up to date: $key $os"
				continue
			fi
			log "stale: $key $os: ${stale[*]}"
		fi

		for arch in "${archs[@]}"; do
			lanes=$(jq -c --arg key "$key" --arg os "$os" --arg arch "$arch" --arg targets "${targets[*]}" --argjson vars "$vars" \
				'. + [{version: $key, os: $os, arch: $arch, targets: $targets,
					vars: ($vars + {PLATFORMS: "linux/\($arch)", CACHE_REF: "ghcr.io/mintopia/php:cache-\($key)-\($os)-\($arch)"})}]' <<<"$lanes")
		done

		[ ${#archs[@]} -eq 2 ] || continue
		for t in "${targets[@]}"; do
			merges=$(jq -c --arg key "$key" --arg os "$os" --arg t "$t" --argjson stable "$stable" --arg latest "$latest" \
				'. + [{version: $key, os: $os, variant: $t, stable: $stable, latest: $latest}]' <<<"$merges")
		done
	done
done

if $dry_run || [ -z "${GITHUB_OUTPUT:-}" ]; then
	jq -n --argjson lanes "$lanes" --argjson merges "$merges" '{lanes: $lanes, merges: $merges}'
else
	{ echo "lanes=$lanes"; echo "merges=$merges"; } >> "$GITHUB_OUTPUT"
	log "$(jq length <<<"$lanes") lanes, $(jq length <<<"$merges") merges"
fi
