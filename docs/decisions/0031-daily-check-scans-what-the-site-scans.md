# Decision: The daily check scans everything the site scans

Status: accepted
Date: 2026-10-26

## Context
The site's CVE scan (ADR 0029) covers OS packages, Go modules, and the components built from source or taken from outside the distro. The daily check (ADR 0022) scanned only OS packages. A CVE in any other component was invisible to the run that decides rebuilds. Each scan also had its own copy of the advisory parsing.

## Decision
- Rule: the daily check and the site scan the same set of components: everything in the images that has a version and a source of advisories.
- `scripts/advisories.sh` fetches and parses the upstream advisories for PHP, FrankenPHP, the PIE extensions, grpc, PIE, s6-overlay and nginx. `scripts/scan-cves.sh` and `scripts/resolve-matrix.sh` both call it. A component added to the images is added there, and gets a `net.mintopia.[ext.]<name>.version` label.
- Images carry a `net.mintopia.pie.version` label, so PIE is matched like the others.
- The daily check's stale rules are those of ADR 0022, except for rule 3. For a target that is otherwise up to date, Trivy scans its amd64 SBOM for OS packages and Go modules (`--pkg-types os,library --ignore-unfixed`), and its labels and PHP version are matched against the advisories.
  - A fixable OS package CVE makes the target stale, because the `PKG_STAMP` upgrade layer picks up the fix on rebuild. nginx findings are dropped, as on the site.
  - Go module and upstream advisory hits are logged as "CVEs a rebuild does not fix". Go modules are pinned by FrankenPHP, and the other components are pinned by their version. Every component tracks its latest upstream release, so a fix arrives as a label change (rule 2). Older patch lanes keep their own PHP version (ADR 0017).
- An advisory that lists several patched lines, like "1.83.1 and 1.82.2", gets one range per fixed line, plus an open range for older lines. A pre-release suffix like `-RC1` is dropped from patched versions.
- A failed scan or advisory fetch logs a warning and does not stale the target.

## Consequences
- An upstream CVE shows in the daily run's log as soon as its advisory is published, not only on the site.
- Each daily run makes one more set of advisory API calls, about a dozen.
- Unfixed CVEs never trigger rebuilds, so they can't loop a target through daily rebuilds.
- Adding the PIE label changes every PHP image's expected labels, so the first run after this change rebuilds them all, as the grpc change does.

## Supersedes
0022-daily-check-rebuilds-stale-targets.md
