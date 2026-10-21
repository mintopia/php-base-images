#!/usr/bin/env bash
set -euo pipefail

[ $# -ge 4 ] || { echo "usage: $0 <full-php-version> <stable:true|false> <os> <variant> [latest-stable-minor]" >&2; exit 64; }
full=$1 stable=$2 os=$3 variant=$4 latest=${5:-8.5}

if [ "$variant" = nginx ]; then
	echo "$os"
	[ "$os" != alpine ] || echo latest
	exit 0
fi

minor=$(cut -d. -f1,2 <<<"$full")
if [[ $full =~ ^[0-9]+\.[0-9]+\.[0-9]+RC([0-9]+)$ ]]; then
	versions=("$minor-rc${BASH_REMATCH[1]}" "$minor")
else
	versions=("$full" "$minor")
fi
if [ "$stable" = true ] && [ "$minor" = "$latest" ]; then
	versions+=("${minor%%.*}" "")
fi
oses=("$os")
[ "$os" != alpine ] || oses+=("")
variants=("$variant")
[ "$variant" != cli ] || variants+=("")

for v in "${versions[@]}"; do
	for o in "${oses[@]}"; do
		for t in "${variants[@]}"; do
			tag=$(printf '%s\n' "$v" "$o" "$t" | sed '/^$/d' | paste -sd- -)
			echo "${tag:-latest}"
		done
	done
done
[ "$stable" = true ] || [ "$os-$variant" != alpine-cli ] || echo unstable
