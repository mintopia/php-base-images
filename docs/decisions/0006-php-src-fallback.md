# Decision: Build PHP from php-src as an opt-in fallback

Status: accepted
Date: 2026-10-21

## Context
Every PHP Target builds on the official `php:*-zts-*` and `php:*-fpm-*` images. When docker-library is slow to publish a new release or RC, or a new Alpine release, our images wait with it. We need a way to ship a PHP release as soon as php-src tags it, without giving up the upstream images as the normal path.

## Decision
`PHP_SOURCE` (`upstream` default, `src`) selects where PHP comes from, per PHP version: optional `"source": "src"` in `versions.json`, overridable for a run with `resolve-matrix.sh --source` or the `php_source` workflow_dispatch input.

In `src` mode `php-src.Dockerfile` builds drop-in `zts` and `fpm` images from the php-src git tag in `PHP_TAG` (latest tag for the minor, RCs included for Unstable versions), and bake `contexts` substitute them for the `php:*` images. Dockerfiles and tags are unchanged.

- The tarball is made with php-src's `makedist` on the build platform, so the generated files are not compiled under emulation.
- configure flags, CFLAGS and LDFLAGS match docker-library per version (ZTS + embed for `zts`, FPM ZTS from 8.6).
- `docker-php-*` helpers are vendored unmodified from docker-library/php at a pinned SHA.
- Trixie keeps `PHPIZE_DEPS` installed, as upstream does, so the ADR 0005 purge works the same.

## Consequences
- An `src` lane compiles PHP twice (zts, fpm), about 10 minutes per arch, cached in the registry under `${CACHE_REF}-src-zts` and `-src-fpm`.
- We own the configure flags and must track docker-library changes when we use this path.
- ADR 0001 is unaffected: `cli` and `frankenphp` still share the ZTS build, now from `src-zts`.
- ADR 0005 is unaffected: trixie images are still purged and flattened.
- ADR 0003: `src` images record `net.mintopia.php.source=php-src`, `net.mintopia.php.tag` and the OS base digest instead of the php image digest. A new php-src tag, or switching source either way, makes the lane stale.

## Supersedes
None
