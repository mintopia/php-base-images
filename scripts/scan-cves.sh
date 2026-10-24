#!/usr/bin/env bash
set -euo pipefail

# Scans the amd64 SBOM of every recorded build for OS package CVEs.
# Prints {scanned, builds: {<digest>: {fixable: [{id, severity, pkg, fixed}], unfixed: {<severity>: n}}}}.
# SBOMs never change for a digest, so <work-dir>/sbom can be cached between runs.
[ $# -eq 2 ] || { echo "usage: $0 <records-dir> <work-dir>" >&2; exit 64; }
records=$1 work=$2
trivy=aquasec/trivy:0.76.1
mkdir -p "$work/sbom" "$work/cache"
rm -rf "$work/out" && mkdir "$work/out"

fetch() {
	local f=$work/sbom/${1#*@sha256:}.json
	[ -s "$f" ] && return 0
	if docker buildx imagetools inspect "$1" --format '{{ json (index .SBOM "linux/amd64").SPDX }}' > "$f.tmp" 2>/dev/null && [ -s "$f.tmp" ]; then
		mv "$f.tmp" "$f"
	else
		rm -f "$f.tmp"
		echo "warning: no SBOM for $1" >&2
	fi
}
export -f fetch
export work

# shellcheck disable=SC2016 # expands in the child shell
jq -r '"\(.image)@\(.digest)"' "$records"/*.json | sort -u | xargs -P 8 -n 1 bash -c 'fetch "$0"'

# BuildKit SBOMs carry no OS package, so trivy needs the distro from the purls
: > "$work/list"
for ref in $(jq -r '"\(.image)@\(.digest)"' "$records"/*.json | sort -u); do
	d=${ref#*@sha256:}
	[ -s "$work/sbom/$d.json" ] || continue
	distro=$(jq -r '[.packages[].externalRefs[]?.referenceLocator | capture("^pkg:(apk|deb)/.*[?&]distro=(?<d>[a-z]+-[0-9.]+)").d][0] // empty' "$work/sbom/$d.json")
	[ -z "$distro" ] || echo "$d ${distro/-//}" >> "$work/list"
done

docker run --rm --user "$(id -u):$(id -g)" -v "$(cd "$work" && pwd):/work" -e TRIVY_CACHE_DIR=/work/cache --entrypoint sh "$trivy" -c '
	trivy image --download-db-only -q
	while read -r d distro; do
		trivy sbom -q --skip-db-update --distro "$distro" --pkg-types os --format json "/work/sbom/$d.json" > "/work/out/$d.json" \
			|| { rm -f "/work/out/$d.json"; echo "warning: scan failed: $d" >&2; }
	done < /work/list'

jq -n --arg scanned "$(date -u +%FT%TZ)" '
	{scanned: $scanned, builds: (reduce inputs as $r ({};
		([$r.Results[]?.Vulnerabilities[]?] | unique_by(.VulnerabilityID)) as $v
		| .["sha256:" + (input_filename | split("/") | last | rtrimstr(".json"))] = {
			fixable: [$v[] | select(.FixedVersion // "" != "") | {id: .VulnerabilityID, severity: .Severity, pkg: .PkgName, fixed: .FixedVersion}],
			unfixed: ([$v[] | select(.FixedVersion // "" == "") | .Severity] | group_by(.) | map({key: .[0], value: length}) | from_entries)}))}' \
	"$work"/out/*.json
