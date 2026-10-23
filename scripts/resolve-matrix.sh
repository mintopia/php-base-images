#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 [--all] [--php VERSION] [--os OS] [--arch ARCH] [--source upstream|src] [--no-patches]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
all=false patches=true only_php='' only_os='' only_arch='' only_source=''
while [ $# -gt 0 ]; do
	case $1 in
		--all) all=true ;;
		--no-patches) patches=false ;;
		--php) only_php=${2:?}; shift ;;
		--os) only_os=${2:?}; shift ;;
		--arch) only_arch=${2:?}; shift ;;
		--source) only_source=${2:?}; shift ;;
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

trivy=aquasec/trivy:0.76.1
trivy_dir=$(mktemp -d)
trap 'rm -rf "$trivy_dir"' EXIT

# CVEs in OS packages that have a fixed package available; the PKG_STAMP upgrade layer picks those up on rebuild
fixable_cves() {
	local distro
	docker buildx imagetools inspect "$1" --format "{{ json (index .SBOM \"$2\").SPDX }}" > "$trivy_dir/sbom.json" || return 1
	distro=$(jq -r '[.packages[].externalRefs[]?.referenceLocator | capture("^pkg:(apk|deb)/.*[?&]distro=(?<d>[a-z]+-[0-9.]+)").d][0] // empty' "$trivy_dir/sbom.json")
	[ -n "$distro" ] || return 1
	docker run --rm --user "$(id -u):$(id -g)" -v "$trivy_dir:/work" -e TRIVY_CACHE_DIR=/work/cache "$trivy" sbom -q --distro "${distro/-//}" \
		--pkg-types os --ignore-unfixed --format json /work/sbom.json \
		| jq -r '[.Results[]?.Vulnerabilities[]?.VulnerabilityID] | unique | if length > 0 then "\(length): \(.[:3] | join(","))" else empty end'
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
apcu=$(packagist apcu/apcu)
mongodb=$(packagist mongodb/mongodb-extension)
otel=$(packagist open-telemetry/ext-opentelemetry)
protobuf=$(packagist pie-extensions/protobuf)
s6=$(github_release just-containers/s6-overlay)
common=$(jq -n --arg redis "$redis" --arg apcu "$apcu" --arg mongodb "$mongodb" --arg otel "$otel" --arg protobuf "$protobuf" --arg s6 "$s6" --arg stamp "$(date -u +%F)" \
	'{REDIS_VERSION: $redis, APCU_VERSION: $apcu, MONGODB_VERSION: $mongodb, OPENTELEMETRY_VERSION: $otel, PROTOBUF_VERSION: $protobuf, S6_OVERLAY_VERSION: $s6, PKG_STAMP: $stamp}')

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
		($vars.PHP_SOURCE == "src" and $v != "nginx") as $src
		| {grpc: "GRPC_VERSION", redis: "REDIS_VERSION", apcu: "APCU_VERSION", mongodb: "MONGODB_VERSION", opentelemetry: "OPENTELEMETRY_VERSION", protobuf: "PROTOBUF_VERSION"} as $ev
		| {cli: "ZTS_DIGEST", frankenphp: "FRANKENPHP_DIGEST", "php-fpm": "FPM_DIGEST", "php-fpm-nginx": "FPM_DIGEST", nginx: "NGINX_BASE_DIGEST"} as $base
		| {"org.opencontainers.image.base.digest": $vars[if $src then "NGINX_BASE_DIGEST" else $base[$v] end]}
		+ (if $src then {"net.mintopia.php.source": "php-src", "net.mintopia.php.tag": $vars.PHP_TAG} else {} end)
		+ (if $src and $v == "frankenphp" and $vars.FRANKENPHP_SRC_VERSION then {"net.mintopia.frankenphp.version": $vars.FRANKENPHP_SRC_VERSION} else {} end)
		+ (if $v == "nginx" then {} else [$exts[] | select($ev[.]) | {key: "net.mintopia.ext.\(.).version", value: $vars[$ev[.]]}] | from_entries end)
		+ (if $v == "nginx" or $v == "php-fpm-nginx" then {"net.mintopia.nginx.version": $vars.NGINX_VERSION} else {} end)
		+ (if $v == "php-fpm-nginx" then {"net.mintopia.s6.version": $vars.S6_OVERLAY_VERSION} else {} end)'
}

# "X.Y.Z os" for every patch release published to GHCR
published_patches() {
	local token last='' page
	token=$(curl -fsSL --retry 3 "https://ghcr.io/token?scope=repository:mintopia/php:pull" | jq -r .token)
	while page=$(curl -fsSL --retry 3 -H "Authorization: Bearer $token" "https://ghcr.io/v2/mintopia/php/tags/list?n=1000&last=$last" | jq -r '.tags // [] | .[]') && [ -n "$page" ]; do
		sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+)-(alpine|trixie)-cli$/\1 \2/p' <<<"$page"
		last=$(tail -1 <<<"$page")
	done
}

frankenphp_src=''
# plan <versions.json key> <lane> <php source> <php-src tag> <os...>: sets plan_lanes and plan_merges
# lane is the key for the current patch, or X.Y.Z for an older patch that keeps only its own tags
plan() {
	local key=$1 lane=$2 php_source=$3 php_tag=$4; shift 4
	local patch=false version tag exts stable src_vars fp sha os targets frankenphp zts fpm vars image minor grpc nginx base
	local stale rebuild t ref reasons published exp arch diff cves
	[ "$lane" = "$key" ] || patch=true
	plan_lanes='[]' plan_merges='[]'
	version=$(jq -c --arg k "$key" '.[$k]' <<<"$matrix")
	tag=$(jq -r .tag <<<"$version")
	exts=$(jq -c .extensions <<<"$version")
	stable=$(jq -r .stable <<<"$version")
	src_vars='{"PHP_SOURCE": "upstream"}'
	if [ "$php_source" = src ]; then
		src_vars=$(jq -c -n --arg t "$php_tag" '{PHP_SOURCE: "src", PHP_TAG: $t}')
		if [ "$(jq -r .frankenphp <<<"$version")" = true ]; then
			if [ -z "$frankenphp_src" ]; then
				fp=$(github_release php/frankenphp)
				# pins the tarball the build fetches to the one seen here
				sha=$(safe "$(curl -fsSL --retry 3 "https://github.com/php/frankenphp/archive/refs/tags/v$fp.tar.gz" | sha256sum | cut -d' ' -f1)")
				frankenphp_src=$(jq -c -n --arg v "$fp" --arg s "$sha" '{FRANKENPHP_SRC_VERSION: $v, FRANKENPHP_SRC_SHA256: $s}')
			fi
			src_vars=$(jq -c --argjson fp "$frankenphp_src" '. + $fp' <<<"$src_vars")
		fi
	fi
	for os in "$@"; do
		[ -n "${os_vars[$os]:-}" ] || continue
		jq -e --arg os "$os" '.os | index($os)' <<<"$version" >/dev/null || continue
		targets=(cli php-fpm php-fpm-nginx)
		frankenphp=''
		if [ "$(jq -r .frankenphp <<<"$version")" = true ]; then
			targets+=(frankenphp)
			[ "$php_source" = src ] || frankenphp=$(digest "dunglas/frankenphp:1-php$tag-$os")
		fi
		$patch || [ "$key" != "$nginx_key" ] || targets+=(nginx)
		zts='' fpm=''
		if [ "$php_source" != src ]; then
			zts=$(digest "php:$tag-zts-$os")
			fpm=$(digest "php:$tag-fpm-$os")
		fi
		vars=$(jq -c --arg key "$key" --arg zts "$zts" --arg fpm "$fpm" --arg fp "$frankenphp" --argjson src "$src_vars" \
			'. + {PHP_VERSION: $key, ZTS_DIGEST: $zts, FPM_DIGEST: $fpm, FRANKENPHP_DIGEST: $fp} + $src' <<<"${os_vars[$os]}")
		if [ "$os" = alpine ]; then
			# php images can lag alpine:3; grpc.sh asserts the distro grpc version
			image=php:$tag-zts-alpine@$zts
			[ "$php_source" != src ] || image=alpine:3@$(digest alpine:3)
			minor=$(safe "$(docker run --rm -q "$image" cut -d. -f1,2 /etc/alpine-release)")
			grpc=$(apk_version "https://dl-cdn.alpinelinux.org/alpine/v$minor/community/x86_64/APKINDEX.tar.gz" grpc-dev)
			nginx=$(apk_version "https://nginx.org/packages/alpine/v$minor/main/x86_64/APKINDEX.tar.gz" nginx)
			base=$(digest "alpine:$minor")
			vars=$(jq -c --arg grpc "$grpc" --arg nginx "$nginx" --arg alpine "$minor" --arg base "$base" \
				'. + {GRPC_VERSION: $grpc, NGINX_VERSION: $nginx, ALPINE_VERSION: $alpine, NGINX_BASE_DIGEST: $base}' <<<"$vars")
		fi

		# every publish is permanent, so only stale targets are rebuilt; an older patch never gains targets it was not published with
		if ! $all || $patch; then
			stale=() rebuild=()
			for t in "${targets[@]}"; do
				if [ "$t" = nginx ]; then ref=ghcr.io/mintopia/nginx:$os; else ref=ghcr.io/mintopia/php:$lane-$os-$t; fi
				reasons=()
				if published=$(docker buildx imagetools inspect "$ref" --format '{{json .Image}}' 2>/dev/null); then
					if $all; then
						reasons=(forced)
					else
						exp=$(expected_labels "$t" "$vars" "$exts")
						for arch in "${archs[@]}"; do
							diff=$(jq -r --arg p "linux/$arch" --argjson exp "$exp" \
								'(.[$p].config.Labels // {}) as $a | [$exp | to_entries[] | select(.value != $a[.key]) | .key] | join(",")' <<<"$published")
							[ -z "$diff" ] || reasons+=("$arch($diff)")
						done
						if [ ${#reasons[@]} -eq 0 ]; then
							cves=$(fixable_cves "$ref" "linux/${archs[0]}") || { log "warning: CVE scan failed: $ref"; cves=''; }
							[ -z "$cves" ] || reasons+=("fixable CVEs $cves")
						fi
					fi
				elif $patch; then
					continue
				else
					reasons=(missing)
				fi
				[ ${#reasons[@]} -eq 0 ] || { stale+=("$t: ${reasons[*]}"); rebuild+=("$t"); }
			done
			if [ ${#rebuild[@]} -eq 0 ]; then
				log "up to date: $lane $os"
				continue
			fi
			log "stale: $lane $os: $(IFS=';'; echo "${stale[*]}")"
			targets=("${rebuild[@]}")
		fi

		for arch in "${archs[@]}"; do
			plan_lanes=$(jq -c --arg lane "$lane" --arg os "$os" --arg arch "$arch" --arg targets "${targets[*]}" --argjson vars "$vars" \
				'. + [{version: $lane, os: $os, arch: $arch, targets: $targets,
					vars: ($vars + {PLATFORMS: "linux/\($arch)", CACHE_REF: "ghcr.io/mintopia/php-base-images-cache:\($lane)-\($os)-\($arch)"})}]' <<<"$plan_lanes")
		done

		[ ${#archs[@]} -eq 2 ] || continue
		for t in "${targets[@]}"; do
			plan_merges=$(jq -c --arg lane "$lane" --arg os "$os" --arg t "$t" --argjson stable "$stable" --arg latest "$latest" --argjson patch "$patch" \
				'. + [{version: $lane, os: $os, variant: $t, stable: $stable, latest: $latest, patch: $patch}]' <<<"$plan_merges")
		done
	done
}

patch_tags=''
! $patches || patch_tags=$(published_patches)

# one entry per versions.json key; build.yml runs each as its own reusable workflow call, so the 256-job matrix limit is per key
plans='{}'
for key in "${selected[@]}"; do
	stable=$(jq -r --arg k "$key" '.[$k].stable' <<<"$matrix")
	php_source=${only_source:-$(jq -r --arg k "$key" '.[$k].source // "src"' <<<"$matrix")}
	[[ $php_source =~ ^(upstream|src)$ ]] || { log "$key: source must be upstream or src, got '$php_source'"; exit 1; }
	unstable=()
	[ "$stable" = true ] || unstable=(--unstable)
	php_tag=$(safe "$("$root/scripts/resolve-php-tag.sh" "$key" "${unstable[@]}")")
	plan "$key" "$key" "$php_source" "$php_tag" alpine trixie
	lanes=$plan_lanes merges=$plan_merges

	# older patches build from php-src: upstream stops refreshing an image once its patch is superseded
	# ponytail: newest patches first; any past the 256-job limit wait for a later daily check
	while read -r older os; do
		[ "php-$older" != "$php_tag" ] || continue
		plan "$key" "$older" src "php-$older" "$os"
		l=$(jq -c --argjson p "$plan_lanes" '. + $p' <<<"$lanes")
		m=$(jq -c --argjson p "$plan_merges" '. + $p' <<<"$merges")
		if [ "$(jq length <<<"$l")" -le 256 ] && [ "$(jq length <<<"$m")" -le 256 ]; then
			lanes=$l merges=$m
		else
			log "deferred, matrix full: $older $os"
		fi
	done < <(awk -v k="$key" 'split($1, a, ".") == 3 && a[1] "." a[2] == k' <<<"$patch_tags" | sort -rV)

	[ "$lanes" = '[]' ] || plans=$(jq -c --arg k "$key" --argjson l "$lanes" --argjson m "$merges" '. + {($k): {lanes: $l, merges: $m}}' <<<"$plans")
done

if [ -z "${GITHUB_OUTPUT:-}" ]; then
	jq . <<<"$plans"
else
	{ echo "plans=$plans"; echo "versions=$(jq -c keys <<<"$plans")"; } >> "$GITHUB_OUTPUT"
	log "$(jq -r 'to_entries | map("\(.key): \(.value.lanes | length) lanes, \(.value.merges | length) merges") | join("; ")' <<<"$plans")"
fi
