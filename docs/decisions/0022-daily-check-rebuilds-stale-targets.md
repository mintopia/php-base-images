# Decision: The daily check rebuilds only the targets that are stale

Status: superseded
Date: 2026-10-24

## Context
Every publish is permanent and visible on the site (ADR 0026, ADR 0027). A rebuild for one target should not republish the others, and a fixed CVE should not wait for a version change.

## Decision
The daily upstream check judges each target on its own. A target is stale when any of these is true, checked in this order:

1. The target is not published.
2. A label (ADR 0021) differs from current upstream on either architecture.
3. The amd64 image has an OS package CVE with a fix available. `scripts/resolve-matrix.sh` scans the image's SBOM with a pinned Trivy (`--pkg-types os --ignore-unfixed`). A failed scan logs a warning and does not stale the target.
4. The oldest architecture was built more than 30 days ago, from the image config's `created` time. This check runs only for targets that are not already stale.

Only stale targets are built and merged. Their shared stages come from the cache (ADR 0023), and the other targets keep their digests and tags. A stale target that keeps failing is retried on the next daily run.

Full rebuilds (ADR 0019) are not scheduled.

## Consequences
- An upstream change publishes only the images it affects.
- Rebuilds spread through the month, because each target's build date drifts. Targets published together stay in step until one of them rebuilds.
- Each daily run scans every target's SBOM.
- A CVE in PHP, an extension, FrankenPHP, nginx or s6-overlay needs a version change, because the scan only covers OS packages.

## Supersedes
None
