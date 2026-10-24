# Decision: Build PHP from php-src by default

Status: accepted
Date: 2026-10-21

## Context
ADR 0006 added `PHP_SOURCE=src` as an opt-in fallback for when the official `php` images lag a release. The src path is now proven across the full matrix: every Lane (8.2–8.6 × alpine/trixie × amd64/arm64) built and passed smoke for every Variant in CI, with module sets matching the upstream-based images and smaller images. Keeping upstream as the default means waiting on docker-library for every release only to switch over when it is slow.

## Decision
`src` is the default PHP source: `PHP_SOURCE` defaults to `src` in `docker-bake.hcl`, and a version with no `source` in `versions.json` resolves to `src`. `"source": "upstream"`, `resolve-matrix.sh --source upstream` or the `php_source: upstream` dispatch input build on the official images instead. Everything else in ADR 0006 (bake contexts, `makedist`, docker-library-parity configure flags, vendored `docker-php-*`, FrankenPHP built against our ZTS libphp) stands.

## Consequences
- Releases ship when php-src tags them, not when docker-library publishes.
- Every Lane compiles PHP once (one ZTS build serves zts, fpm and FrankenPHP's libphp) plus FrankenPHP itself; cold builds take about 10 minutes longer per arch. The registry cache covers rebuilds where the tag is unchanged.
- We own configure flags and build deps for every version, and must track docker-library changes.
- Local `docker buildx bake` needs `PHP_TAG` (from `scripts/resolve-php-tag.sh`), or `PHP_SOURCE=upstream`.
- Published images switch base: `org.opencontainers.image.base.*` names alpine / debian:trixie-slim, and `net.mintopia.php.{source,tag}` labels appear. The first daily run after merge sees every Lane as stale and rebuilds it.

## Supersedes
0006-php-src-fallback.md
