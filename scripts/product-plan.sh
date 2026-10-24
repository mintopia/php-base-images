#!/usr/bin/env bash
# Reads product-keys.sh output and prints "build=<names>" and "restore=<names>", space-padded for contains().
# build: no cache entry on main, or one created over 30 days ago; and every product when php builds,
#   so nothing is built against an older php. Existing entries are deleted first, so the new ones can be saved.
# restore: last used 5 or more days ago, so the 7-day eviction never reaches it; and php when anything builds from it.
set -euo pipefail

gh=${GH:-gh}
now=${NOW:-$(date +%s)}
ref=refs/heads/main
input=$(cat)
prefix=$(sed -n 's/^prefix=//p' <<<"$input")
[ -n "$prefix" ] || { echo "no prefix= line" >&2; exit 64; }
# one lookup per leg: every key of the leg starts with the prefix
caches=$("$gh" api "repos/$GITHUB_REPOSITORY/actions/caches?key=$prefix&ref=$ref&per_page=100" --jq '.actions_caches')

names=() keys=() actions=()
while IFS='=' read -r name key; do
	[ "$name" != prefix ] && [ -n "$key" ] || continue
	entry=$(jq -c --arg k "$key" '[.[] | select(.key == $k)] | first // empty' <<<"$caches")
	action=''
	if [ -n "$entry" ]; then
		read -r created accessed < <(jq -r '[.created_at, .last_accessed_at] | map(sub("\\.[0-9]+"; "") | fromdateiso8601) | @tsv' <<<"$entry")
		if [ "$created" -le $((now - 30 * 86400)) ]; then action=build
		elif [ "$accessed" -le $((now - 5 * 86400)) ]; then action=restore
		fi
	else
		action=build
	fi
	names+=("$name") keys+=("$key") actions+=("$action")
done <<<"$input"

php_build=false
for i in "${!names[@]}"; do
	[ "${names[$i]}" != php ] || [ "${actions[$i]}" != build ] || php_build=true
done

build=' ' restore=' '
for i in "${!names[@]}"; do
	! $php_build || actions[i]=build
	case ${actions[$i]} in
		build)
			if jq -e --arg k "${keys[$i]}" 'any(.[]; .key == $k)' <<<"$caches" > /dev/null; then
				"$gh" api -X DELETE "repos/$GITHUB_REPOSITORY/actions/caches?key=${keys[$i]}&ref=$ref" > /dev/null
			fi
			build+="${names[$i]} " ;;
		restore) restore+="${names[$i]} " ;;
	esac
done

if [ "$build" != ' ' ] && ! $php_build && [[ $restore != *' php '* ]]; then
	restore+='php '
fi
echo "build=$build"
echo "restore=$restore"
