#!/usr/bin/env bash
set -euo pipefail

# Scans the amd64 SBOM of every recorded build for OS package and Go module CVEs, and fetches advisories for components built from source.
# Prints {scanned, advisories: {<component>: [{id, url, severity, ranges: [{from?, above?, below?, upto?, fixed}]}]}, builds: {<digest>: [{id, severity, pkg, fixed, kind?}]}}, kind "upstream" for Go modules.
# Components are named as in a build's net.mintopia.[ext.]<name>.version labels, plus php.
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
		trivy sbom -q --skip-db-update --distro "$distro" --pkg-types os,library --format json "/work/sbom/$d.json" > "/work/out/$d.json" \
			|| { rm -f "/work/out/$d.json"; echo "warning: scan failed: $d" >&2; }
	done < /work/list'

# built from source, so not in the SBOM: <component> <repo> [regex for the advisory package ecosystems that version it]
advisories=$work/advisories
rm -rf "$advisories" && mkdir "$advisories"
while read -r c repo eco; do
	gh api --paginate "repos/$repo/security-advisories?per_page=100" | jq -s --arg c "$c" --arg eco "$eco" '
		# pecl/protobuf 5.35.1 is protobuf release 35.1, the version its label carries
		def ver: if $c == "protobuf" then sub("^[0-9]+\\."; "") else . end;
		def bounds: reduce (scan("(>=|=>|<=|=<|>|<|=)?\\s*v?([0-9](?:[0-9.]*[0-9])?)") | {op: (.[0] // "="), v: (.[1] | ver)}) as $t ({};
			if $t.op == ">=" or $t.op == "=>" then .from = $t.v
			elif $t.op == ">" then .above = $t.v
			elif $t.op == "<" then .below = $t.v
			elif $t.op == "<=" or $t.op == "=<" then .upto = $t.v
			else .from = $t.v | .upto = $t.v end);
		[add[] | {id: (.cve_id // .ghsa_id), url: .html_url, severity: (.severity // "unknown" | ascii_upcase | sub("MODERATE"; "MEDIUM")),
			ranges: [.vulnerabilities[] | select(.package.ecosystem // "" | test($eco))
				| ([.patched_versions // "" | scan("[0-9](?:[0-9.]*[0-9])?")][0] // "" | ver) as $patched
				| .vulnerable_version_range // "" | gsub("-[0-9A-Za-z.]+"; "") | bounds | select(length > 0) | .fixed = (.below // $patched)]}
			| select(.ranges | length > 0)
			# one range per release line, like "< 8.2.34" and "< 8.3.35", each starting at its own line
			| if (.ranges | length) > 1 then .ranges |= map(if .from or .above then . else .from = ((.below // .upto) | split(".")[:-1] | join(".")) end) else . end]' \
		> "$advisories/$c.json"
done <<'COMPONENTS'
php php/php-src
frankenphp php/frankenphp ^(go)?$
apcu krakjoe/apcu
grpc grpc/grpc php
mongodb mongodb/mongo-php-driver ^pecl$
opentelemetry open-telemetry/opentelemetry-php-instrumentation
protobuf protocolbuffers/protobuf ^pecl$
redis phpredis/phpredis
COMPONENTS

# nginx comes from nginx.org's packages, which distro advisories don't cover, so nginx.org's own advisories do
curl -fsSL --retry 3 https://nginx.org/en/security_advisories.html | jq -Rs '
	[split("</p>")[] | capture("Severity: (?:<b>)?(?<sev>[a-z]+).*CVERecord\\?id=(?<id>CVE-[0-9-]+).*Not vulnerable: (?<ok>[^<]*)<br>Vulnerable: (?<bad>[^<]*)"; "s")
		| [.ok | scan("[0-9][0-9.]*[0-9]")] as $ok
		| def line: split(".")[:2] | join(".");
		def key: split(".") | map(tonumber);
		# "Vulnerable: 0.1.29-1.31.6" spans release lines that "Not vulnerable: 1.31.7+, 1.30.6+" each fix at their own patch
		{id, url: "https://www.cve.org/CVERecord?id=\(.id)", severity: ({major: "HIGH"}[.sev] // (.sev | ascii_upcase)),
			ranges: [.bad | split(",")[] | [scan("[0-9][0-9.]*[0-9]")] | select(length > 0) | {from: .[0], upto: .[-1]} as $r
				| if $ok == [] then $r + {fixed: ""}
					else ($r + {below: ($ok | min_by(key) | line), fixed: ($ok | join(", "))}),
						($ok[] | {from: ([$r.from, line] | max_by(key)), below: ., upto: $r.upto, fixed: .}) end]}
		| select(.ranges | length > 0)]' > "$advisories/nginx.json"

jq -n --arg scanned "$(date -u +%FT%TZ)" --argjson advisories "$(jq -n '[inputs | {key: (input_filename | split("/") | last | rtrimstr(".json")), value: .}] | from_entries' "$advisories"/*.json)" '
	{scanned: $scanned, advisories: $advisories, builds: (reduce inputs as $r ({};
		.["sha256:" + (input_filename | split("/") | last | rtrimstr(".json"))] =
			# nginx.org packages share the distro package name, so distro advisories misjudge them; nginx.org advisories cover them
			([$r.Results[]? | .Class as $class | .Vulnerabilities[]? | select(.PkgName != "nginx") | .class = $class] | unique_by(.VulnerabilityID)
				| map({id: .VulnerabilityID, severity: .Severity, pkg: .PkgName, fixed: (.FixedVersion // "")} + (if .class == "os-pkgs" then {} else {kind: "upstream"} end)))))}' \
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
