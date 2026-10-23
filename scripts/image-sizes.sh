#!/usr/bin/env bash
set -euo pipefail

# Prints the compressed (pull) size of each linux platform in an image index, as {"amd64": bytes, ...}.
[ $# -eq 1 ] || { echo "usage: $0 <image@digest>" >&2; exit 64; }
repo=${1%@*}
docker buildx imagetools inspect --raw "$1" |
	jq -r '.manifests[] | select(.platform.os == "linux") | "\(.platform.architecture) \(.digest)"' |
	while read -r arch digest; do
		docker buildx imagetools inspect --raw "$repo@$digest" |
			jq -c --arg a "$arch" '{($a): (([.layers[].size] | add) + .config.size)}'
	done | jq -s -c 'add // {}'
