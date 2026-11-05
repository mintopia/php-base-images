# shellcheck shell=sh
# Sourced. retry <cmd...>: runs cmd up to 3 times with a growing pause, for GitHub's transient 5xx and auth blips.
retry() {
	retry_n=1
	until "$@"; do
		[ "$retry_n" -lt 3 ] || return 1
		sleep $((retry_n * 15))
		retry_n=$((retry_n + 1))
	done
}
