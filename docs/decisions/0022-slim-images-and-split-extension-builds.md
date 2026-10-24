# Decision: Slim PHP images and build each extension in its own stage

Status: accepted
Date: 2026-10-24

## Context
A review of the images found that the cli and fpm images shipped `php-cgi`, `phpdbg` and `libphp.so` (about 24 MB each, about 70 MB in all), and that the extension `.so` files were unstripped (mongodb.so alone was 12 MB). The extension layer also copied extensions the base image already had. One RUN built every extension, so a version bump of any one rebuilt all of them, including grpc. The PHP tag and tarball sat in `php-base`, so every patch release reinstalled the builder dev packages. Each lane also ran bake twice: once to load images for the smoke test, and again to push.

## Decision
- php-src builds with `--disable-cgi --disable-phpdbg`. `libphp.so` (embed) ships only in the frankenphp image. Man pages are removed.
- intl, zip, exif, sockets, gmp and soap are built as shared extensions in the php-src configure step, not afterwards with `install-php-extensions` (the set in ADR 0014 is unchanged). On the upstream source path `install-php-extensions` still builds them.
- Extensions are built in one stage each (`ext-bundled`, `ext-grpc`, `ext-<pie package>`), in parallel from a shared `ext-base`. Each stage outputs only its new, stripped `.so` and ini files and its runtime dependencies, and a `scratch` stage `ext` merges them. `EXT_BUILDER` selects the base (zts, or nts for upstream fpm).
- The PHP tag and tarball are added after the builder dependency layers.
- A lane runs bake once, with a `docker` output for the smoke test and, when publishing, a push-by-digest output to the cache package with SBOM and provenance. A failed smoke test still blocks the merge, because the digests artifact is uploaded only after it passes.
- Final-stage COPYs use `--link`.
- `/usr/src/php.tar.xz` stays, so `docker-php-source` and `docker-php-ext-install` keep working in derived images.

## Consequences
- cli and fpm images are roughly 85 MB smaller uncompressed.
- `php-cgi`, `phpdbg` and the embed SAPI are no longer in cli or fpm. Anyone relying on them has to build their own image. `phpize`, `php-config` and the headers remain, so derived images can still build extensions.
- More stages mean more intermediate cache entries, while a bump of one extension rebuilds only that extension.
- Images are pushed to the cache package before the smoke test runs; a failing lane leaves an orphaned digest there, which the cache cleanup removes.

## Supersedes
None (amends how ADR 0014's extensions are built)
