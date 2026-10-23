# Decision: Every published patch release stays maintained

Status: accepted
Date: 2026-10-23

## Context
Lanes are one per `versions.json` minor and always build its latest php-src tag. Once 8.5.12 ships, `8.5.11-*` tags stop moving: users pinned to a patch get no OS, extension or CVE fixes.

## Decision
- Every `X.Y.Z` patch with a published `X.Y.Z-<os>-cli` tag on GHCR, under a minor still in `versions.json`, gets its own lane (`version: X.Y.Z`) pinned to `php-X.Y.Z`. GHCR tags are the record of what was published (ADR 0003).
- Patch lanes go through the same upstream check (labels, fixable CVEs) and the same full rebuilds (`--all`) as the current lane.
- A patch lane always builds from php-src, rebuilds only targets it was published with, never builds nginx, and its merge pushes only the `X.Y.Z*` tags from `scripts/tags.sh`.
- Release candidates are not patch releases and are not maintained once superseded.
- Pull requests skip patch lanes (`--no-patches`).
- GitHub caps a matrix at 256 jobs. Each PHP version runs as its own workflow call (ADR 0019), so the cap is per minor: its patch lanes are added newest first until either matrix would pass 256, and the rest are logged as deferred for a later daily check.

## Consequences
- Pinning to `X.Y.Z` is safe: the tag keeps receiving fixes for as long as its minor is in `versions.json`. Removing a minor stops all its patches.
- Daily runs do one more CVE scan per patch target, and full rebuilds grow by four lanes per patch.
- The cap delays rebuilds once a single minor has roughly 25 maintained patches, about two years of releases. Retire old patches or merge per lane instead of per variant before then.
- Patch builds are recorded with `version: X.Y.Z`; the site does not list them yet.

## Supersedes
None
