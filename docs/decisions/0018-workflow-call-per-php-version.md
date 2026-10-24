# Decision: Each PHP version runs its own reusable workflow call

Status: accepted
Date: 2026-10-24

## Context
A single build and merge matrix for every PHP version and patch is capped at 256 jobs, and it would reach that within months. It also makes every merge wait for the slowest build of any PHP version. PHP minors are a small, fixed set, and each adds one a year.

## Decision
- `scripts/resolve-matrix.sh` outputs a plan for each `versions.json` key (`plans`), and the keys that have work (`versions`).
- `build.yml` calls `.github/workflows/lanes.yml` once per key, through a matrix.
- Each call runs its own products, build and merge jobs. The 256-job cap applies to each key's plan.
- Merges run 2 at a time per key, to stay under GHCR's 2000 requests a minute while several keys merge at once.
- `site` waits for every key's call.

## Consequences
- A PHP version publishes as soon as its own builds finish.
- Job names in the Actions UI are prefixed with `php <version> /`.
- Up to 20 builds per key run in parallel. The account's concurrent job limit is the real ceiling.

## Supersedes
None
