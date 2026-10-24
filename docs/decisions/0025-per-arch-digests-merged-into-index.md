# Decision: Per-arch images are pushed by digest and merged into one index

Status: accepted
Date: 2026-10-24

## Context
A multi-arch tag needs both architectures, but the two Lanes for an OS and PHP version finish at different times. The image must not be tagged until both have passed their smoke test.

## Decision
- Each Lane pushes its per-arch image by digest, with no tag, into `ghcr.io/mintopia/php` (or `ghcr.io/mintopia/nginx` for nginx). The push includes BuildKit SBOM and max provenance attestations. Pushes retry 3 times with a growing pause, because GHCR allows 2000 requests a minute across all Lanes.
- Each Lane records its digests as a workflow artifact.
- The merge job, one per Variant, runs 2 at a time per PHP version. It:
  - creates the multi-arch index from the two per-arch digests with `docker buildx imagetools create`, tagged by `scripts/tags.sh`;
  - signs the index with keyless cosign;
  - records the image's metadata (ADR 0027);
  - deletes the per-arch index it consumed.
- The merge does not delete the per-arch image's platform images or attestations. The multi-arch index references them.

## Consequences
- A failed run, or a merge that fails before its last step, leaves untagged per-arch indexes in `php` or `nginx`, with their platform images and attestations. Nothing removes them (ADR 0026).
- The merge needs admin access to the packages, which the repository has by default.
- Verify a published tag with `cosign verify` against the GitHub Actions identity.

## Supersedes
None
