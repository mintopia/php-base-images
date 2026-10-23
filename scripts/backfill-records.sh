#!/usr/bin/env bash
set -euo pipefail

# Writes a build record for every published image on GHCR, in the merge job's record format.
# A rebuild moves the tags, so superseded builds are untagged multi-arch indexes; they count too.
# Reruns skip digests already recorded in <out-dir>.
[ $# -eq 1 ] || { echo "usage: $0 <out-dir>" >&2; exit 64; }
out=$1
root=$(cd "$(dirname "$0")/.." && pwd)
matrix=$(jq -c '.variable.VERSIONS.default' "$root/versions.json")
latest=$(jq -r 'to_entries | map(select(.value.stable) | .key)[]' <<<"$matrix" | sort -V | tail -1)
mkdir -p "$out"

record() { # <image> <digest> <created> <tags, or - for none> <platforms json>
	local image=$1 digest=$2 created=$3 tags=$4 platforms=$5 os variant version='' config modules='[]' sizes full names=()
	[ "$tags" = - ] || IFS=, read -ra names <<<"$tags"
	config=$(docker buildx imagetools inspect "$image@$digest" --format '{{json .Image}}' 2>/dev/null |
		jq -c '.["linux/amd64"].config // empty') || return 0
	[ -n "$config" ] || return 0
	if [ ${#names[@]} -eq 0 ]; then
		case $(jq -r '.Labels["org.opencontainers.image.base.name"] // ""' <<<"$config") in
			*alpine*) os=alpine ;; *trixie*) os=trixie ;; *) return 0 ;;
		esac
		case $(jq -r '((.Cmd // [])[0] // "") + " " + ((.Entrypoint // []) | join(" "))' <<<"$config") in
			nginx*) variant=nginx ;; php-fpm*) variant=php-fpm ;; frankenphp*) variant=frankenphp ;;
			php\ *) variant=cli ;; *" /init"*) variant=php-fpm-nginx ;; *) return 0 ;;
		esac
		if [ "$variant" = nginx ]; then version=$latest
		# without tags the PHP version must come from the image itself
		elif ! jq -e '.Labels["org.opencontainers.image.version"] // (.Env // [] | map(select(startswith("PHP_VERSION="))) | first)' <<<"$config" >/dev/null; then return 0
		fi
	elif [[ $image == */nginx ]]; then
		os=$(printf '%s\n' "${names[@]}" | grep -xE 'alpine|trixie' | head -1) || return 0
		variant=nginx version=$latest
	else
		full=$(printf '%s\n' "${names[@]}" | grep -E -- '-(alpine|trixie)-(cli|php-fpm|php-fpm-nginx|frankenphp)$' | head -1) || return 0
		[[ $full =~ -(alpine|trixie)-(cli|php-fpm|php-fpm-nginx|frankenphp)$ ]]
		os=${BASH_REMATCH[1]} variant=${BASH_REMATCH[2]}
	fi
	# the site only shows modules for live builds, which are always tagged
	if [ "$variant" != nginx ] && [ ${#names[@]} -gt 0 ]; then
		modules=$(docker run --rm --pull always --entrypoint php "$image@$digest" -m </dev/null |
			jq -R -s -c 'split("\n") | map(select(length > 0 and (startswith("[") | not))) | unique')
		docker image rm -f "$image@$digest" >/dev/null 2>&1 || true
	fi
	sizes=$("$root/scripts/image-sizes.sh" "$image@$digest") || sizes='{}'
	jq -n -c --argjson config "$config" --arg time "$created" --arg image "$image" --arg os "$os" --arg variant "$variant" \
		--arg version "$version" --arg digest "$digest" --argjson platforms "$platforms" --argjson matrix "$matrix" \
		--argjson modules "$modules" --argjson sizes "$sizes" \
		'($config.Labels // {}) as $l
		# early builds predate the version label; recover it from PHP_VERSION or the tags
		| ($l["org.opencontainers.image.version"]
			// ($config.Env // [] | map(select(startswith("PHP_VERSION=")) | sub("^PHP_VERSION="; "")) | first)
			// ([$ARGS.positional[]
			| (capture("^(?<v>[0-9]+\\.[0-9]+\\.[0-9]+)-").v // (capture("^(?<m>[0-9]+\\.[0-9]+)-rc(?<r>[0-9]+)-") | "\(.m).0RC\(.r)"))
			] | first) // "") as $v
		| (if $variant == "nginx" then $version else ($v | split(".")[:2] | join(".")) end) as $key
		| {time: $time, run: "backfill", commit: ($l["org.opencontainers.image.revision"] // ""), image: $image,
			version: $key, os: $os, variant: $variant, php: (if $variant == "nginx" then "" else $v end),
			stable: ($matrix[$key].stable // false), digest: $digest, platforms: $platforms,
			tags: $ARGS.positional, modules: $modules, sizes: $sizes, labels: $l}' --args ${names[@]+"${names[@]}"} \
		>"$out/${created//:/}-${image##*/}-$os-$variant-${digest#sha256:}.json"
	echo "recorded $image ${tags/#-/untagged} $digest" >&2
}
export -f record
export out root matrix latest

# Find the published indexes serially, cheaply: the API lists newest first, so an index comes before the
# platform and attestation manifests it references, which are then skipped without a registry call.
# Inspecting and recording run in parallel.
for package in php nginx; do
	image=ghcr.io/mintopia/$package
	children=' '
	# shellcheck disable=SC2016
	gh api --paginate "/users/mintopia/packages/container/$package/versions" \
		--jq '.[] | (.metadata.container.tags) as $t
			| select(($t | length) == 0 or ([$t[] | select(endswith(".sig") or startswith("cache-") | not)] | length > 0))
			| [.name, .created_at, ($t | join(","))] | @tsv' |
	while IFS=$'\t' read -r digest created tags; do
		[[ $children == *" $digest "* ]] && continue
		done_file=$(compgen -G "$out/*-${digest#sha256:}.json" | head -1) || true
		if [ -n "$done_file" ]; then
			children+="$(jq -r '.platforms[]' "$done_file" | tr '\n' ' ') "
			continue
		fi
		raw=$(docker buildx imagetools inspect --raw "$image@$digest" 2>/dev/null) || continue
		jq -e '.manifests | length > 0' <<<"$raw" >/dev/null 2>&1 || continue
		children+="$(jq -r '.manifests[].digest' <<<"$raw" | tr '\n' ' ') "
		platforms=$(jq -c '[.manifests[] | select(.platform.os == "linux") | {key: .platform.architecture, value: .digest}] | from_entries' <<<"$raw")
		# single-platform indexes are lane pushes the merge job never published
		[ "$(jq length <<<"$platforms")" -ge 2 ] || continue
		printf '%s\0%s\0%s\0%s\0%s\0' "$image" "$digest" "$created" "${tags:--}" "$platforms"
	done
done | xargs -0 -n 5 -P 8 bash -c 'record "$@"' _
