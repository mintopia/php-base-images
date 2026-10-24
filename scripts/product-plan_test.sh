#!/usr/bin/env bash
set -euo pipefail

plan=$(cd "$(dirname "$0")" && pwd)/product-plan.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
day=86400
now=$((100 * day))
iso() { jq -rn --argjson t "$1" '$t | todate | sub("Z$"; ".000Z")'; }

# fake gh: answers cache lookups from $work/caches.json, records deletes
cat > "$work/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$2" = -X ]; then echo "$4" >> "$WORK/deleted"; exit 0; fi
key=${2#*key=}; key=${key%%&*}
jq -c --arg k "$key" '{actions_caches: [.[] | select(.key | startswith($k))]}' "$WORK/caches.json" | jq -c "$4"
EOF
chmod +x "$work/gh"

# check <name> <expected build> <expected restore> <expected deletes> <caches json>, lines on stdin
check() {
	local name=$1 build=$2 restore=$3 deletes=$4 out
	echo "$5" > "$work/caches.json"
	: > "$work/deleted"
	out=$(GH="$work/gh" WORK="$work" NOW=$now GITHUB_REPOSITORY=o/r "$plan")
	[ "$(sed -n 's/^build=//p' <<<"$out")" = "$build" ] || { echo "FAIL [$name] build: $out"; failed=1; }
	[ "$(sed -n 's/^restore=//p' <<<"$out")" = "$restore" ] || { echo "FAIL [$name] restore: $out"; failed=1; }
	[ "$(grep -c . "$work/deleted")" = "$deletes" ] || { echo "FAIL [$name] deletes: $(cat "$work/deleted")"; failed=1; }
}
entry() { jq -cn --arg k "$1" --arg c "$(iso $((now - $2 * day)))" --arg a "$(iso $((now - $3 * day)))" '{key: $k, created_at: $c, last_accessed_at: $a}'; }

keys=$'php=php-k\next-grpc=ext-grpc-k'
check "all missing" ' php ext-grpc ' ' ' 0 '[]' <<<"$keys"
check "all fresh" ' ' ' ' 0 "[$(entry php-k 1 1), $(entry ext-grpc-k 1 1)]" <<<"$keys"
check "idle 5 days" ' ' ' php ' 0 "[$(entry php-k 10 5), $(entry ext-grpc-k 10 4)]" <<<"$keys"
check "ext missing restores php" ' ext-grpc ' ' php ' 0 "[$(entry php-k 1 1)]" <<<"$keys"
check "php over 30 days" ' php ' ' ' 1 "[$(entry php-k 30 1), $(entry ext-grpc-k 1 1)]" <<<"$keys"
check "prefix is not a match" ' php ' ' ' 0 "[$(entry php-k-other 1 1), $(entry ext-grpc-k 1 1)]" <<<"$keys"

[ "$failed" = 0 ] && echo "product-plan_test: ok"
exit "$failed"
