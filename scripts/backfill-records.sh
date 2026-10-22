#!/usr/bin/env bash
set -euo pipefail

# Writes a build record for every tagged image on GHCR, in the merge job's record format.
[ $# -eq 1 ] || { echo "usage: $0 <out-dir>" >&2; exit 64; }
out=$1
root=$(cd "$(dirname "$0")/.." && pwd)
matrix=$(jq -c '.variable.VERSIONS.default' "$root/versions.json")
latest=$(jq -r 'to_entries | map(select(.value.stable) | .key)[]' <<<"$matrix" | sort -V | tail -1)
mkdir -p "$out"

for package in php nginx; do
	image=ghcr.io/mintopia/$package
	gh api --paginate "/users/mintopia/packages/container/$package/versions" \
		--jq '.[] | select([.metadata.container.tags[] | select(endswith(".sig") or startswith("cache-") | not)] | length > 0)
			| [.name, .created_at, (.metadata.container.tags | join(","))] | @tsv' |
	while IFS=$'\t' read -r digest created tags; do
		IFS=, read -ra names <<<"$tags"
		if [ "$package" = nginx ]; then
			os=$(printf '%s\n' "${names[@]}" | grep -xE 'alpine|trixie' | head -1) || continue
			variant=nginx version=$latest
		else
			full=$(printf '%s\n' "${names[@]}" | grep -E -- '-(alpine|trixie)-(cli|php-fpm|php-fpm-nginx|frankenphp)$' | head -1) || continue
			[[ $full =~ -(alpine|trixie)-(cli|php-fpm|php-fpm-nginx|frankenphp)$ ]]
			os=${BASH_REMATCH[1]} variant=${BASH_REMATCH[2]} version=''
		fi
		platforms=$(docker buildx imagetools inspect "$image@$digest" --format '{{json .Manifest}}' |
			jq -c '[.manifests[] | select(.platform.os == "linux") | {key: .platform.architecture, value: .digest}] | from_entries')
		modules='[]'
		[ "$variant" = nginx ] || modules=$(docker run --rm --pull always --entrypoint php "$image@$digest" -m </dev/null |
			jq -R -s -c 'split("\n") | map(select(length > 0 and (startswith("[") | not))) | unique')
		docker image rm -f "$image@$digest" >/dev/null 2>&1 || true
		docker buildx imagetools inspect "$image@$digest" --format '{{json .Image}}' |
			jq -c --arg time "$created" --arg image "$image" --arg os "$os" --arg variant "$variant" --arg version "$version" \
				--arg digest "$digest" --argjson platforms "$platforms" --argjson matrix "$matrix" --argjson modules "$modules" \
				'(.["linux/amd64"].config.Labels // {}) as $l
				# early builds predate the version label; recover it from the tags
				| ($l["org.opencontainers.image.version"] // ([$ARGS.positional[]
					| (capture("^(?<v>[0-9]+\\.[0-9]+\\.[0-9]+)-").v // (capture("^(?<m>[0-9]+\\.[0-9]+)-rc(?<r>[0-9]+)-") | "\(.m).0RC\(.r)"))
					] | first) // "") as $v
				| (if $variant == "nginx" then $version else ($v | split(".")[:2] | join(".")) end) as $key
				| {time: $time, run: "backfill", commit: ($l["org.opencontainers.image.revision"] // ""), image: $image,
					version: $key, os: $os, variant: $variant, php: (if $variant == "nginx" then "" else $v end),
					stable: ($matrix[$key].stable // false), digest: $digest, platforms: $platforms,
					tags: $ARGS.positional, modules: $modules, labels: $l}' --args "${names[@]}" \
			> "$out/${created//:/}-$package-$os-$variant-${digest#sha256:}.json"
		echo "recorded $image $tags" >&2
	done
done
