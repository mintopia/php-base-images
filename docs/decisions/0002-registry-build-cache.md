# Decision: BuildKit cache lives in GHCR, not the GitHub Actions cache

Status: superseded
Date: 2026-10-21

## Context
20 build lanes (5 PHP versions × 2 OS × 2 arch), each with `mode=max` layer export, far exceed the 10 GB per-repo GitHub Actions cache. Eviction would make every build a cold build; grpc alone is a 20+ minute cold step.

## Decision
Each lane exports and imports BuildKit cache to registry refs `ghcr.io/mintopia/php:cache-<ver>-<os>-<arch>-<variant>` with `mode=max`, one ref per target because bake targets exporting to a shared ref overwrite each other.

## Consequences
- Cache refs are visible as tags in the package; documented as not for consumption.
- No size cap; stale cache refs accumulate until overwritten (one ref per lane, so bounded).
- Cross-lane sharing is impossible by design; same-lane rebuilds are near-instant when upstream is unchanged.
- Five cache refs per lane (100 total); bounded, overwritten in place.

## Supersedes
None
