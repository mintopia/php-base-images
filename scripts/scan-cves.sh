#!/usr/bin/env bash
set -euo pipefail

# Scans the amd64 SBOM of every recorded build for OS package CVEs.
# Prints {scanned, php: [{id, url, severity, fixed: [X.Y.Z]}], builds: {<digest>: [{id, severity, pkg, fixed}]}}.
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

# PHP is compiled from php-src, so the SBOM holds no PHP package; php-src's advisories cover it
php=$work/php.json
gh api --paginate 'repos/php/php-src/security-advisories?per_page=100' \
	-q '.[] | {id: (.cve_id // .ghsa_id), url: .html_url, severity: (.severity | ascii_upcase), fixed: [.vulnerabilities[].patched_versions | select(. != null)]}' \
	| jq -s . > "$php"

jq -n --arg scanned "$(date -u +%FT%TZ)" --slurpfile php "$php" '
	{scanned: $scanned, php: $php[0], builds: (reduce inputs as $r ({};
		.["sha256:" + (input_filename | split("/") | last | rtrimstr(".json"))] =
			([$r.Results[]?.Vulnerabilities[]?] | unique_by(.VulnerabilityID)
				| map({id: .VulnerabilityID, severity: .Severity, pkg: .PkgName, fixed: (.FixedVersion // "")}))))}' \
	"$work"/out/*.json > "$work/scan.json"

# Alpine and Debian publish no severity, so trivy falls back to NVD; the CVE's own CNA rating on CVE.org wins
# ponytail: only criticals are re-rated, since only they are flagged
# one file per CVE, refetched weekly in case the CNA adds or revises a rating
mkdir -p "$work/cna"
find "$work/cna" -type f -mtime +7 -delete
cna='{}'
for id in $(jq -r '[.builds[][] | select(.severity == "CRITICAL") | .id] | unique[]' "$work/scan.json"); do
	f=$work/cna/$id
	if [ ! -f "$f" ]; then
		if curl -fsSL --retry 3 "https://cveawg.mitre.org/api/cve/$id" \
			| jq -r '[.containers.cna.metrics[]? | (.cvssV4_0 // .cvssV3_1 // .cvssV3_0 // empty).baseSeverity][0] // empty' > "$f.tmp"; then
			mv "$f.tmp" "$f"
		else
			rm -f "$f.tmp"
		fi
	fi
	sev=$(cat "$f" 2>/dev/null) || sev=''
	[ -z "$sev" ] || cna=$(jq -c --arg id "$id" --arg s "$sev" '. + {($id): $s}' <<<"$cna")
done
jq --argjson cna "$cna" '.builds |= map_values(map(.severity = ($cna[.id] // .severity)))' "$work/scan.json"
