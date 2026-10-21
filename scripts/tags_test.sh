#!/usr/bin/env bash
set -euo pipefail

tags=$(dirname "$0")/tags.sh
failed=0

check() {
	local args=$1 mode=$2 tag out argv
	shift 2
	read -ra argv <<<"$args"
	out=$("$tags" "${argv[@]}")
	for tag in "$@"; do
		if grep -qxF -- "$tag" <<<"$out"; then
			[ "$mode" = has ] || { echo "FAIL [$args] unexpected $tag"; failed=1; }
		else
			[ "$mode" = lacks ] || { echo "FAIL [$args] missing $tag"; failed=1; }
		fi
	done
}

check "8.5.11 true alpine cli" has latest 8 8.5 8.5.11 alpine cli 8-alpine 8.5-cli alpine-cli 8.5.11-alpine-cli
check "8.5.11 true alpine cli" lacks unstable ""
check "8.5.11 true trixie frankenphp" has trixie-frankenphp 8-trixie-frankenphp 8.5.11-trixie-frankenphp
check "8.5.11 true trixie frankenphp" lacks latest frankenphp trixie 8.5
check "8.6.0RC3 false trixie php-fpm" has 8.6-rc3-trixie-php-fpm 8.6-trixie-php-fpm
check "8.6.0RC3 false trixie php-fpm" lacks 8-trixie-php-fpm trixie-php-fpm 8.6.0RC3-trixie-php-fpm unstable
check "8.6.0RC3 false alpine cli" has unstable 8.6 8.6-rc3 8.6-alpine-cli
check "8.6.0RC3 false alpine cli" lacks latest 8
check "8.4.26 true alpine cli" has 8.4 8.4.26 8.4-alpine 8.4.26-cli
check "8.4.26 true alpine cli" lacks latest 8 alpine cli
check "8.5.11 true trixie nginx" has trixie
check "8.5.11 true trixie nginx" lacks latest
check "8.5.11 true alpine nginx" has alpine latest
[ "$("$tags" 8.5.11 true trixie nginx)" = trixie ] || { echo "FAIL nginx trixie not exactly 'trixie'"; failed=1; }
[ "$("$tags" 8.5.11 true alpine cli | sort | uniq -d)" = "" ] || { echo "FAIL duplicate tags"; failed=1; }

[ "$failed" = 0 ] && echo "tags_test: ok"
exit "$failed"
