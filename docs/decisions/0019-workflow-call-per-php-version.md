# Decision: Each PHP version builds in its own reusable workflow call

Status: accepted
Date: 2026-10-23

## Context
ADR 0018 adds a lane for every maintained patch release. A single build and merge matrix is capped at 256 jobs and would hit that within months. One matrix also makes every merge wait for the slowest build of any PHP version. PHP minors are a small, fixed set that grows by one a year.

## Decision
- `resolve-matrix.sh` outputs one plan per `versions.json` key (`plans`) and the keys that have work (`versions`).
- `build.yml` calls `.github/workflows/lanes.yml` once per key through a matrix. `lanes.yml` holds the build and merge jobs unchanged.
- The 256-job cap applies to each key's plan on its own.
- Merges run 2 at a time per key instead of 6 overall, to stay under GHCR's 2000 requests a minute with several keys merging at once.

## Consequences
- A PHP version publishes as soon as its own builds finish.
- Job names in the Actions UI are prefixed `php <version> /`.
- Up to 20 builds per key run in parallel; the account's concurrent job limit is the real ceiling.
- `site` waits for every key's call.

## Supersedes
None
