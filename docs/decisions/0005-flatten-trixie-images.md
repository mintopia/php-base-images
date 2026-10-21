# Decision: Trixie PHP images are flattened to a single layer

Status: accepted
Date: 2026-10-21

## Context
Upstream `php:*-trixie` images keep the full build toolchain (`PHPIZE_DEPS`: gcc, make, autoconf and friends) in their layers, so `php:8.5-zts-trixie` is around 780 MB before any extension. Purging those packages in our layer removes nothing from the pull because the files live in upstream's layers. Alpine images do not have this problem.

## Decision
Trixie `cli`, `php-fpm`, `php-fpm-nginx` and `frankenphp` purge `PHPIZE_DEPS`, then the final stage is `FROM scratch` with a single `COPY --from` of the purged filesystem, re-declaring ENV, WORKDIR, EXPOSE, ENTRYPOINT and CMD. The standalone `nginx` target and all Alpine targets stay layered.

## Consequences
- Roughly half the pull size for trixie PHP images.
- No layer sharing with upstream; every rebuild pushes one full layer. The registry build cache still makes rebuilds fast.
- Base-image provenance in attestations is lost; `org.opencontainers.image.base.*` labels still record it.
- `install-php-extensions` still works in the image because it installs build tools on demand; PIE needs them installed first.

## Supersedes
None
