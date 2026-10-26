#!/usr/bin/env bash
set -euo pipefail

# Writes <out-dir>/<component>.json for each component built from source or outside the distro, so not covered by the SBOM scan:
# [{id, url, severity, ranges: [{from?, above?, below?, upto?, fixed}]}]. Components are named as in a build's
# net.mintopia.[ext.]<name>.version labels, plus php. Shared by the site's CVE scan and the daily check (ADR 0029, ADR 0030).
[ $# -eq 1 ] || { echo "usage: $0 <out-dir>" >&2; exit 64; }
out=$1
rm -rf "$out" && mkdir -p "$out"

# <component> <repo> [regex for the advisory package ecosystems that version it]
while read -r c repo eco; do
	gh api --paginate "repos/$repo/security-advisories?per_page=100" | jq -s --arg c "$c" --arg eco "$eco" '
		# pecl/protobuf 5.35.1 is protobuf release 35.1, the version its label carries
		def ver: if $c == "protobuf" then sub("^[0-9]+\\."; "") else . end;
		def key: [scan("[0-9]+") | tonumber];
		def line: split(".")[:-1] | join(".");
		def bounds: reduce (scan("(>=|=>|<=|=<|>|<|=)?\\s*v?([0-9](?:[0-9.]*[0-9])?)") | {op: (.[0] // "="), v: (.[1] | ver)}) as $t ({};
			if $t.op == ">=" or $t.op == "=>" then .from = $t.v
			elif $t.op == ">" then .above = $t.v
			elif $t.op == "<" then .below = $t.v
			elif $t.op == "<=" or $t.op == "=<" then .upto = $t.v
			else .from = $t.v | .upto = $t.v end);
		[add[] | {id: (.cve_id // .ghsa_id), url: .html_url, severity: (.severity // "unknown" | ascii_upcase | sub("MODERATE"; "MEDIUM")),
			ranges: [.vulnerabilities[] | select(.package.ecosystem // "" | test($eco))
				| [.patched_versions // "" | gsub("-[0-9A-Za-z.]+"; "") | scan("[0-9](?:[0-9.]*[0-9])?") | ver] as $patched
				| .vulnerable_version_range // "" | gsub("-[0-9A-Za-z.]+"; "") | bounds | select(length > 0)
				# "<= 1.83.0" fixed in "1.83.1 and 1.82.2": lines older than every fix stay open, each fixed line ends at its fix
				| if ($patched | length) > 1 and (.below | not) and (.from == null or .from != .upto) then
					(. + {from: (.from // (if .above then null else "0" end)), below: ([$patched[] | line] | min_by(key)), fixed: ($patched | join(", "))} | with_entries(select(.value != null))),
					(. as $r | $patched[] | . as $p | $r + {from: ([$r.from // "0", ($p | line)] | max_by(key)), below: $p, fixed: $p})
				else (if .below or .upto then . else .below = $patched[0] end) | with_entries(select(.value != null)) | .fixed = (.below // $patched[0] // "") end]}
			| select(.ranges | length > 0)
			# one range per release line, like "< 8.2.34" and "< 8.3.35", each starting at its own line
			| if (.ranges | length) > 1 then .ranges |= map(if .from or .above then . else .from = ((.below // .upto) | line) end) else . end]' \
		> "$out/$c.json"
done <<'COMPONENTS'
php php/php-src
frankenphp php/frankenphp ^(go)?$
apcu krakjoe/apcu
grpc grpc/grpc php
mongodb mongodb/mongo-php-driver ^pecl$
opentelemetry open-telemetry/opentelemetry-php-instrumentation
protobuf protocolbuffers/protobuf ^pecl$
redis phpredis/phpredis
pie php/pie
s6 just-containers/s6-overlay
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
		| select(.ranges | length > 0)]' > "$out/nginx.json"
