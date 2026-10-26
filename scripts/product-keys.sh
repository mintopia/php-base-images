#!/usr/bin/env bash
# Prints "prefix=<leg prefix>" and "<product>=<cache key>" for each build product of the Lane in the bake variables (ADR 0023).
# Every key of a leg starts with the prefix, so one cache lookup finds them all.
# A key changes with every input that changes the product's files; the php key is part of every other key.
# --libgrpc prints only libgrpc, which every leg of an OS and arch shares, under its own prefix (ADR 0030).
set -euo pipefail
cd "$(dirname "$0")/.."

arch=${PLATFORMS:-}
arch=${arch#linux/}
[ -n "$arch" ] || { echo "PLATFORMS is required" >&2; exit 64; }

targets=$(docker buildx bake -f docker-bake.hcl -f versions.json --print products product-libgrpc | jq -c .target)
arg() { jq -r --arg t "product-$1" --arg a "$2" '.[$t].args[$a | ascii_upcase] // ""' <<<"$targets"; }
files() { cat "$@" | sha256sum | cut -d' ' -f1; }
key() {
	local name=$1; shift
	echo "$name=$prefix$name-$(printf '%s\n' "$@" | sha256sum | cut -c1-16)"
}

prefix=libgrpc-$OS-$arch-
libgrpc=$(key libgrpc "$(arg libgrpc GRPC_VERSION)" "$OS" "$arch" "$(arg libgrpc ALPINE_VERSION)" "$(files build/libgrpc.sh)")
if [ "${1:-}" = --libgrpc ]; then
	echo "prefix=$prefix"
	echo "$libgrpc"
	exit 0
fi

[ -n "${NGINX_BASE_DIGEST:-}" ] || { echo "NGINX_BASE_DIGEST is required" >&2; exit 64; }
prefix=${PHP_TAG#php-}-$OS-$arch-
echo "prefix=$prefix"

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
			# outside the leg prefix, so product-plan.sh leaves it to the libgrpc job; lanes restore it to build ext-grpc
			echo "$libgrpc"
			key "$t" "$php" "${libgrpc#libgrpc=}" "$(arg "$t" EXTENSIONS)" "$(files build/extensions.sh build/grpc.sh)" ;;
		ext-*)
			v=${t#ext-}
			key "$t" "$php" "$(arg "$t" "${v}_VERSION")" "$(arg "$t" PIE_VERSION)" "$(arg "$t" EXTENSIONS)" "$(files build/extensions.sh)" ;;
	esac
done
