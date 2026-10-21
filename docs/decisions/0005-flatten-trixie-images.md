# Decision: Trixie PHP images stay layered (flattening rejected)

Status: accepted
Date: 2026-10-21

## Context
Upstream `php:*-trixie` images keep the full build toolchain (`PHPIZE_DEPS`) in their layers, so `php:8.5-zts-trixie` is around 780 MB before any extension. Purging those packages in our layer removes nothing from the pull because the files live in upstream's layers. Flattening the final stage with `FROM scratch` + `COPY --from` was tried and roughly halved the images (cli 869 → 528 MB).

## Decision
Keep the trixie images layered on the upstream base. `PHPIZE_DEPS` is still purged so the compilers are absent from the runtime and from scanner output, but no size is reclaimed. Flattening was reverted the same day.

## Consequences
- Trixie PHP images are roughly 800-950 MB; Alpine is the slim choice.
- Layer sharing with upstream and base-image provenance in attestations are preserved; rebuilds push only changed layers.
- Flattening remains available as a one-stage change per target if pull size becomes a problem.

## Supersedes
None
