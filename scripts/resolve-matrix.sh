#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: $0 [--all] [--php VERSION] [--os OS] [--arch ARCH] [--no-patches]" >&2; exit 64; }

root=$(cd "$(dirname "$0")/.." && pwd)
all=false patches=true only_php='' only_os='' only_arch=''
while [ $# -gt 0 ]; do
	case $1 in
		--all) all=true ;;
		--no-patches) patches=false ;;
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

trivy=aquasec/trivy:0.76.1
trivy_dir=$(mktemp -d)
trap 'rm -rf "$trivy_dir"' EXIT

# scans everything the site scans (ADR 0030): OS packages and Go modules from the SBOM, and labelled components against upstream advisories.
# Prints the CVEs a rebuild fixes, fixable OS packages that the PKG_STAMP upgrade layer picks up, as "<n>: <ids>".
# The rest are logged: Go modules are pinned by FrankenPHP and components by their version, so only a new upstream release fixes them.
image_cves() {
	local ref=$1 platform=$2 labels=$3 php=$4 distro upstream
	docker buildx imagetools inspect "$ref" --format "{{ json (index .SBOM \"$platform\").SPDX }}" > "$trivy_dir/sbom.json" || return 1
	distro=$(jq -r '[.packages[].externalRefs[]?.referenceLocator | capture("^pkg:(apk|deb)/.*[?&]distro=(?<d>[a-z]+-[0-9.]+)").d][0] // empty' "$trivy_dir/sbom.json")
	[ -n "$distro" ] || return 1
	docker run --rm --user "$(id -u):$(id -g)" -v "$trivy_dir:/work" -e TRIVY_CACHE_DIR=/work/cache "$trivy" sbom -q --distro "${distro/-//}" \
		--pkg-types os,library --ignore-unfixed --format json /work/sbom.json > "$trivy_dir/scan.json" || return 1
	if [ ! -d "$trivy_dir/advisories" ]; then
		"$root/scripts/advisories.sh" "$trivy_dir/advisories" || { log "warning: advisory fetch failed"; mkdir -p "$trivy_dir/advisories"; echo '[]' > "$trivy_dir/advisories/none.json"; }
	fi
	upstream=$(jq -n -r --slurpfile scan "$trivy_dir/scan.json" --argjson labels "$labels" --arg php "$php" '
		def key: [scan("[0-9]+") | tonumber];
		def within($v): (.from == null or ($v | key) >= (.from | key)) and (.above == null or ($v | key) > (.above | key))
			and (.below == null or ($v | key) < (.below | key)) and (.upto == null or ($v | key) <= (.upto | key));
		(reduce inputs as $a ({}; .[input_filename | split("/") | last | rtrimstr(".json")] = $a)) as $adv
		| [$labels | to_entries[] | {c: (.key | capture("^net\\.mintopia\\.(?:ext\\.)?(?<c>[a-z0-9]+)\\.version$").c), v: .value}]
			+ (if $php == "" then [] else [{c: "php", v: $php}] end)
		| [.[] as $x | ($adv[$x.c] // [])[] | select(any(.ranges[]; within($x.v))) | "\($x.c) \($x.v) \(.id)"]
			+ [$scan[0].Results[]? | select(.Class != "os-pkgs") | .Vulnerabilities[]? | "\(.PkgName) \(.InstalledVersion) \(.VulnerabilityID)"]
		| unique | join(", ")' "$trivy_dir/advisories"/*.json)
	[ -z "$upstream" ] || log "CVEs a rebuild does not fix: $ref: $upstream"
	# nginx.org packages share the distro package name, so distro advisories misjudge them; nginx.org advisories cover them
	jq -r '[.Results[]? | select(.Class == "os-pkgs") | .Vulnerabilities[]? | select(.PkgName != "nginx") | .VulnerabilityID] | unique
		| if length > 0 then "\(length): \(.[:3] | join(","))" else empty end' "$trivy_dir/scan.json"
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
pie=$(github_release php/pie)
# latest stable grpc release, so security fixes arrive with the version (ADR 0030)
grpc=$(github_release grpc/grpc)
common=$(jq -n --arg redis "$redis" --arg apcu "$apcu" --arg mongodb "$mongodb" --arg otel "$otel" --arg protobuf "$protobuf" --arg s6 "$s6" --arg pie "$pie" --arg grpc "$grpc" --arg stamp "$(date -u +%F)" \
	'{REDIS_VERSION: $redis, APCU_VERSION: $apcu, MONGODB_VERSION: $mongodb, OPENTELEMETRY_VERSION: $otel, PROTOBUF_VERSION: $protobuf, S6_OVERLAY_VERSION: $s6, PIE_VERSION: $pie, GRPC_VERSION: $grpc, PKG_STAMP: $stamp}')

declare -A os_vars
for os in alpine trixie; do
	[ -z "$only_os" ] || [ "$os" = "$only_os" ] || continue
	case $os in
		alpine)
			base='' nginx=''
			;;
		trixie)
			base=$(digest debian:trixie-slim)
			nginx=$(deb_version https://nginx.org/packages/debian/dists/trixie/nginx/binary-amd64/Packages.gz nginx gzip)
			;;
	esac
	os_vars[$os]=$(jq -c --arg os "$os" --arg base "$base" --arg nginx "$nginx" \
		'. + {OS: $os, NGINX_BASE_DIGEST: $base, NGINX_VERSION: $nginx}' <<<"$common")
done
[ ${#os_vars[@]} -gt 0 ] || { log "no OS matches '$only_os'"; exit 1; }

expected_labels() {
	jq -c -n --arg v "$1" --argjson vars "$2" --argjson exts "$3" '
		($v != "nginx") as $src
		| {grpc: "GRPC_VERSION", redis: "REDIS_VERSION", apcu: "APCU_VERSION", mongodb: "MONGODB_VERSION", opentelemetry: "OPENTELEMETRY_VERSION", protobuf: "PROTOBUF_VERSION"} as $ev
		| {"org.opencontainers.image.base.digest": $vars.NGINX_BASE_DIGEST}
		+ (if $src then {"net.mintopia.php.source": "php-src", "net.mintopia.php.tag": $vars.PHP_TAG, "net.mintopia.pie.version": $vars.PIE_VERSION} else {} end)
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
# plan <versions.json key> <lane> <php-src tag> <os...>: sets plan_lanes, plan_merges and plan_products
# plan_products has the current lane on every arch, stale or not, so the products job keeps its build products cached;
# an older patch only gets products for the lanes it builds, so they are saved but may be evicted when idle
# lane is the key for the current patch, or X.Y.Z for an older patch that keeps only its own tags
plan() {
	local key=$1 lane=$2 php_tag=$3; shift 3
	local patch=false version exts stable src_vars fp sha os targets vars minor nginx base
	local stale rebuild t ref reasons published exp arch diff cves built
	[ "$lane" = "$key" ] || patch=true
	plan_lanes='[]' plan_merges='[]' plan_products='[]'
	version=$(jq -c --arg k "$key" '.[$k]' <<<"$matrix")
	exts=$(jq -c .extensions <<<"$version")
	stable=$(jq -r .stable <<<"$version")
	src_vars=$(jq -c -n --arg t "$php_tag" '{PHP_TAG: $t}')
	if [ "$(jq -r .frankenphp <<<"$version")" = true ]; then
		if [ -z "$frankenphp_src" ]; then
			fp=$(github_release php/frankenphp)
			# pins the tarball the build fetches to the one seen here
			sha=$(safe "$(curl -fsSL --retry 3 "https://github.com/php/frankenphp/archive/refs/tags/v$fp.tar.gz" | sha256sum | cut -d' ' -f1)")
			frankenphp_src=$(jq -c -n --arg v "$fp" --arg s "$sha" '{FRANKENPHP_SRC_VERSION: $v, FRANKENPHP_SRC_SHA256: $s}')
		fi
		src_vars=$(jq -c --argjson fp "$frankenphp_src" '. + $fp' <<<"$src_vars")
	fi
	for os in "$@"; do
		[ -n "${os_vars[$os]:-}" ] || continue
		jq -e --arg os "$os" '.os | index($os)' <<<"$version" >/dev/null || continue
		targets=(cli php-fpm php-fpm-nginx)
		[ "$(jq -r .frankenphp <<<"$version")" != true ] || targets+=(frankenphp)
		$patch || [ "$key" != "$nginx_key" ] || targets+=(nginx)
		vars=$(jq -c --arg key "$key" --argjson src "$src_vars" '. + {PHP_VERSION: $key} + $src' <<<"${os_vars[$os]}")
		if [ "$os" = alpine ]; then
			minor=$(safe "$(docker run --rm -q "alpine:3@$(digest alpine:3)" cut -d. -f1,2 /etc/alpine-release)")
			nginx=$(apk_version "https://nginx.org/packages/alpine/v$minor/main/x86_64/APKINDEX.tar.gz" nginx)
			base=$(digest "alpine:$minor")
			vars=$(jq -c --arg nginx "$nginx" --arg alpine "$minor" --arg base "$base" \
				'. + {NGINX_VERSION: $nginx, ALPINE_VERSION: $alpine, NGINX_BASE_DIGEST: $base}' <<<"$vars")
		fi
		if ! $patch; then
			for arch in amd64 arm64; do
				plan_products=$(jq -c --arg lane "$lane" --arg os "$os" --arg arch "$arch" --argjson vars "$vars" \
					'. + [{version: $lane, os: $os, arch: $arch, vars: ($vars + {PLATFORMS: "linux/\($arch)"})}]' <<<"$plan_products")
			done
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
							built=$(jq -r '[.[].created | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601] | min' <<<"$published")
							[ "$built" -gt "$(($(date +%s) - 30 * 86400))" ] || reasons+=("built $(jq -rn --argjson t "$built" '$t | todate'), over 30 days")
						fi
						if [ ${#reasons[@]} -eq 0 ]; then
							cves=$(image_cves "$ref" "linux/${archs[0]}" "$(jq -c --arg p "linux/${archs[0]}" '.[$p].config.Labels // {}' <<<"$published")" \
								"$([ "$t" = nginx ] || echo "${php_tag#php-}")") || { log "warning: CVE scan failed: $ref"; cves=''; }
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
					vars: ($vars + {PLATFORMS: "linux/\($arch)"})}]' <<<"$plan_lanes")
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
	unstable=()
	[ "$stable" = true ] || unstable=(--unstable)
	php_tag=$(safe "$("$root/scripts/resolve-php-tag.sh" "$key" "${unstable[@]}")")
	plan "$key" "$key" "$php_tag" alpine trixie
	lanes=$plan_lanes merges=$plan_merges products=$plan_products

	# ponytail: newest patches first; any past the 256-job limit wait for a later daily check
	while read -r older os; do
		[ "php-$older" != "$php_tag" ] || continue
		plan "$key" "$older" "php-$older" "$os"
		l=$(jq -c --argjson p "$plan_lanes" '. + $p' <<<"$lanes")
		m=$(jq -c --argjson p "$plan_merges" '. + $p' <<<"$merges")
		p=$(jq -c --argjson p "$plan_lanes" '. + ($p | map(del(.targets)))' <<<"$products")
		if [ "$(jq length <<<"$l")" -le 256 ] && [ "$(jq length <<<"$m")" -le 256 ] && [ "$(jq length <<<"$p")" -le 256 ]; then
			lanes=$l merges=$m products=$p
		else
			log "deferred, matrix full: $older $os"
		fi
	done < <(awk -v k="$key" 'split($1, a, ".") == 3 && a[1] "." a[2] == k' <<<"$patch_tags" | sort -rV)

	plans=$(jq -c --arg k "$key" --argjson l "$lanes" --argjson m "$merges" --argjson p "$products" '. + {($k): {lanes: $l, merges: $m, products: $p}}' <<<"$plans")
done

if [ -z "${GITHUB_OUTPUT:-}" ]; then
	jq . <<<"$plans"
else
	# one libgrpc build per OS and arch, from any lane whose version has grpc (ADR 0030)
	libgrpc=$(jq -c --argjson m "$matrix" '[.[].products[] | select($m[.version | split(".")[:2] | join(".")].extensions | index("grpc"))]
		| unique_by([.os, .arch]) | map({os, arch, vars})' <<<"$plans")
	{ echo "plans=$plans"; echo "versions=$(jq -c keys <<<"$plans")"; echo "libgrpc=$libgrpc"; } >> "$GITHUB_OUTPUT"
	log "$(jq -r 'to_entries | map("\(.key): \(.value.lanes | length) lanes, \(.value.merges | length) merges, \(.value.products | length) product lanes") | join("; ")' <<<"$plans")"
fi
