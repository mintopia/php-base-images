#!/bin/sh
# Usage: resolve-tag.sh <minor> [--unstable]  -> latest php-src tag, e.g. php-8.5.11
set -eu
minor="$1"
git ls-remote --tags --refs https://github.com/php/php-src.git "php-$minor.*" \
	| sed 's|.*refs/tags/||' \
	| if [ "${2:-}" = --unstable ]; then cat; else grep -Ev '(alpha|beta|RC)'; fi \
	| sed -E 's/(alpha|beta|RC)/~\1/' | sort -V | sed 's/~//' | tail -1
