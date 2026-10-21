#!/bin/sh
# Usage: resolve-php-tag.sh <minor> [--unstable]  -> latest php-src tag, e.g. php-8.5.11
set -eu
minor="$1"
git ls-remote --tags --refs https://github.com/php/php-src.git "php-$minor.*" \
	| sed 's|.*refs/tags/||' \
	| if [ "${2:-}" = --unstable ]; then cat; else grep -Ev '(alpha|beta|RC)'; fi \
	| sed -e 's/alpha/~a/' -e 's/beta/~b/' -e 's/RC/~r/' | sort -V \
	| sed -e 's/~a/alpha/' -e 's/~b/beta/' -e 's/~r/RC/' | tail -1
