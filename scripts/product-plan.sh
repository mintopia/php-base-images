#!/usr/bin/env bash
# Reads "<product>=<cache key>" lines and prints "build=<names>" and "restore=<names>", space-padded for contains().
# build: no cache entry on main, or one created over 30 days ago (deleted here first, so the new one can be saved).
# restore: last used 5 or more days ago, so the 7-day eviction never reaches it; and php when anything builds from it.
set -euo pipefail

gh=${GH:-gh}
now=${NOW:-$(date +%s)}
ref=refs/heads/main
build=' ' restore=' '

while IFS='=' read -r name key; do
	[ -n "$key" ] || continue
	entry=$("$gh" api "repos/$GITHUB_REPOSITORY/actions/caches?key=$key&ref=$ref" \
		--jq "[.actions_caches[] | select(.key == \"$key\")] | first // empty")
	if [ -n "$entry" ]; then
		read -r created accessed < <(jq -r '[.created_at, .last_accessed_at] | map(sub("\\.[0-9]+"; "") | fromdateiso8601) | @tsv' <<<"$entry")
	fi
	if [ -z "$entry" ] || [ "$created" -le $((now - 30 * 86400)) ]; then
		[ -z "$entry" ] || "$gh" api -X DELETE "repos/$GITHUB_REPOSITORY/actions/caches?key=$key&ref=$ref" > /dev/null
		build+="$name "
	elif [ "$accessed" -le $((now - 5 * 86400)) ]; then
		restore+="$name "
	fi
done

if [ "$build" != ' ' ] && [[ $build != *' php '* ]] && [[ $restore != *' php '* ]]; then
	restore+='php '
fi
echo "build=$build"
echo "restore=$restore"
