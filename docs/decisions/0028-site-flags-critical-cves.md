# Decision: The site flags builds with critical CVEs

Status: accepted
Date: 2026-10-24

## Context
Superseded builds stay pullable by digest (ADR 0026), and pinned users cannot see whether they are exposed. The daily check (ADR 0022) scans images to decide rebuilds, but nothing records the result for users.

## Decision
- Every site build runs `scripts/scan-cves.sh` over every recorded build.
- OS package CVEs come from a Trivy scan of each build's amd64 SBOM, both fixable and unfixed.
- PHP is compiled from php-src, so its CVEs are not in the SBOM. They come from php-src's GitHub security advisories, which give a fixed version per minor. A build on an earlier patch of that minor is affected.
- Alpine and Debian publish no severity, so Trivy falls back to NVD. For a critical CVE, the rating is the one from the CVE's CNA on CVE.org, when the CNA gives one. Lookups are cached per CVE for a week, and in CI through `actions/cache`.
- Only critical CVEs are flagged. Each build's page shows a count, and a per-build CVEs page lists every CVE, de-duplicated by ID.
- Results go only to the site build (`SITE_CVES`), not to `site-data`. They reflect today's vulnerability database, so they are regenerated on every run.
- A failed scan logs a warning, and the site deploys without flags.

## Consequences
- A pinned digest shows new CVEs as they are published, without a rebuild.
- Unfixed lower-severity CVEs, which Debian carries in quantity, do not flag a build.
- Older PHP patch tags keep their PHP CVEs, since only a newer patch fixes them.
- Each site build downloads every SBOM, about 3 MB each. That takes about 2.5 minutes for 385 builds, and the time grows with the record count.
- PIE extensions and grpc are compiled outside the base image's SBOM, so they are not scanned.

## Supersedes
None
