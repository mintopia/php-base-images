#!/usr/bin/env bash
# Prints "prefix=<leg prefix>" and "<product>=<cache key>" for each build product of the Lane in the bake variables (ADR 0023).
# Every key of a leg starts with the prefix, so one cache lookup finds them all.
# A key changes with every input that changes the product's files; the php key is part of every other key.
set -euo pipefail
cd "$(dirname "$0")/.."

arch=${PLATFORMS:-}
arch=${arch#linux/}
if [ -z "$arch" ] || [ -z "${NGINX_BASE_DIGEST:-}" ]; then echo "PLATFORMS and NGINX_BASE_DIGEST are required" >&2; exit 64; fi

targets=$(docker buildx bake -f docker-bake.hcl -f versions.json --print products | jq -c .target)
arg() { jq -r --arg t "product-$1" --arg a "$2" '.[$t].args[$a | ascii_upcase] // ""' <<<"$targets"; }
files() { cat "$@" | sha256sum | cut -d' ' -f1; }
prefix=${PHP_TAG#php-}-$OS-$arch-
echo "prefix=$prefix"
key() {
	local name=$1; shift
	echo "$name=$prefix$name-$(printf '%s\n' "$@" | sha256sum | cut -c1-16)"
}

php=$(key php "$PHP_TAG" "$OS" "$arch" "$NGINX_BASE_DIGEST" "$(files php-src.Dockerfile build/php-src.sh build/docker-php/*)")
echo "$php"
php=${php#php=}
for t in $(jq -r 'keys[] | ltrimstr("product-")' <<<"$targets"); do
	case $t in
		php) ;;
		frankenphp)
			key "$t" "$php" "$(arg "$t" FRANKENPHP_SRC_VERSION)" "$(arg "$t" FRANKENPHP_SRC_SHA256)" "$(arg "$t" GO_VERSION)" \
				"$(arg "$t" WATCHER_VERSION)" "$(files build/frankenphp-src.sh)" ;;
		ext-grpc)
			key "$t" "$php" "$(arg "$t" GRPC_VERSION)" "$(arg "$t" EXTENSIONS)" "$(files build/extensions.sh build/grpc.sh)" ;;
		ext-*)
			v=${t#ext-}
			key "$t" "$php" "$(arg "$t" "${v}_VERSION")" "$(arg "$t" PIE_VERSION)" "$(arg "$t" EXTENSIONS)" "$(files build/extensions.sh)" ;;
	esac
done
