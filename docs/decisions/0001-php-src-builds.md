# Decision: PHP is built from php-src tags

Status: accepted
Date: 2026-10-24

## Context
The official `php` images lag php-src releases, and each release would wait for docker-library to publish. Every Lane needs PHP from the same source, so there is one path and no fallback.

## Decision
- Every Lane compiles PHP from a php-src git tag. The official `php:*` images are not used.
- `scripts/resolve-php-tag.sh` picks the tag: the latest stable tag for the minor. Unstable minors (8.6) use the latest RC tag. Patch lanes use their own `php-X.Y.Z` tag.
- The `src` stage of `php-src.Dockerfile` clones the tag and runs php-src's `makedist` on the build platform, so the tarball is never compiled under emulation.
- `build/php-src.sh` configures PHP with the same flags as docker-library, per version.
- The `docker-php-*` helper scripts are vendored unmodified from docker-library/php at a pinned commit (`build/docker-php/`).
- The base for both OSes is `alpine:3` or `debian:trixie-slim`.
- Images record `net.mintopia.php.source=php-src` and `net.mintopia.php.tag`.

## Consequences
- A php-src tag ships as soon as it exists.
- The project owns the configure flags and must track docker-library changes to them.
- `build/php-src.sh` works around GH-18743 with a sed on the opcache JIT source. Remove it once no supported PHP version needs it.
- A new php-src tag makes every affected Lane stale through the image labels (ADR 0021).

## Supersedes
None
