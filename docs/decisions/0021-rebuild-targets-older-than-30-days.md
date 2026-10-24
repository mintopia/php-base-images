# Decision: Rebuild each target once it is 30 days old

Status: accepted
Date: 2026-10-24

## Context
A monthly cron ran a Full rebuild on the 1st, rebuilding every Lane and every maintained patch whenever it was last built. A target rebuilt on the 28th for a CVE was rebuilt again on the 1st, and every patch tag changed digest on the same day each month.

## Decision
- The daily upstream check adds a third stale reason: the published image's oldest arch was built over 30 days ago, read from the image config's `created`.
- The age check runs after the label check and before the CVE scan; a target already stale skips it.
- The monthly cron is removed. `force`, image-input pushes and pull requests still pass `--all`.

## Consequences
- Each target is rebuilt at most 30 days after its last build, and no sooner unless its inputs or fixable CVEs change.
- Rebuilds spread out over the month instead of landing on the 1st, once targets' build dates drift apart. Targets published together stay in step until something rebuilds one of them.
- A target whose rebuild keeps failing is retried daily until it succeeds.

## Supersedes
The monthly Full rebuild in ADR 0003 and ADR 0016.
