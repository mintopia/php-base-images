# shellcheck shell=sh
# Sourced. Authenticates git with github.com via $GITHUB_TOKEN when set; never traced, the header is the token in base64.
case $- in *x*) set +x; git_auth_trace=1 ;; *) git_auth_trace= ;; esac
if [ -n "${GITHUB_TOKEN:-}" ]; then
	GIT_CONFIG_COUNT=1
	GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
	GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
	export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
fi
[ -z "$git_auth_trace" ] || set -x
