# Decision: Every published patch release stays maintained

Status: accepted
Date: 2026-10-24

## Context
Each Lane builds the latest php-src tag of its minor. Once a newer patch ships, the older `X.Y.Z-*` tags stop moving, and users pinned to them get no OS, extension or CVE fixes.

## Decision
- Each `X.Y.Z` patch that has a published `X.Y.Z-<os>-cli` tag on GHCR, under a minor in `versions.json`, gets its own lane with `version: X.Y.Z`, built from `php-X.Y.Z`. The GHCR tags are the record of what was published (ADR 0021).
- A patch lane goes through the same upstream check and the same full rebuild as the current Lane (ADR 0019, ADR 0022).
- A patch lane rebuilds only the targets it was published with. It never builds nginx.
- Its merge pushes only the `X.Y.Z*` tags from `scripts/tags.sh`.
- RCs are not patch releases and are not maintained once superseded.
- Pull requests skip patch lanes (`--no-patches`).
- GitHub caps a matrix at 256 jobs, and each PHP version runs as its own workflow call (ADR 0018). Patch lanes are added newest first until the job count for a version's build, merge or product matrix would pass 256. The rest are logged as deferred to a later daily run.

## Consequences
- Pinning to `X.Y.Z` keeps receiving fixes for as long as its minor is in `versions.json`. Removing a minor stops all its patches.
- Each patch adds four Lanes to a full rebuild, and one CVE scan per target to each daily run.
- Once a minor has about 25 maintained patches, the cap starts deferring rebuilds. Retire old patches before then.

## Supersedes
None
