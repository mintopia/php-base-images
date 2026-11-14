# shellcheck shell=sh
# Sourced. Authenticates git and Composer/PIE with github.com via $GITHUB_TOKEN when set; never traced, both carry the token.
# PIE ignores $GITHUB_TOKEN and only reads COMPOSER_AUTH; unauthenticated, shared runner IPs hit GitHub's rate limit.
case $- in *x*) set +x; git_auth_trace=1 ;; *) git_auth_trace= ;; esac
if [ -n "${GITHUB_TOKEN:-}" ]; then
	GIT_CONFIG_COUNT=1
	GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
	GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
	COMPOSER_AUTH=$(printf '{"github-oauth":{"github.com":"%s"}}' "$GITHUB_TOKEN")
	export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 COMPOSER_AUTH
fi
[ -z "$git_auth_trace" ] || set -x
