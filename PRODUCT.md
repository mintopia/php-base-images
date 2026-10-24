# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Astro, static output, deployed to GitHub Pages at `php.mintopia.net` via `actions/deploy-pages`. Rebuilt every time images are published.

## Users

Developers and platform engineers choosing a PHP base image for their own Dockerfiles or Compose/Kubernetes manifests. They arrive knowing roughly what they want (a PHP minor, Alpine or Debian, a runtime shape) and need the exact image reference, confidence it contains what they need, and a way to see what changed between builds when something breaks or a CVE lands.

## Product Purpose

The public face of `ghcr.io/mintopia/php` and `ghcr.io/mintopia/nginx`. It answers: which image do I use, what is in it, and what changed. Success: a visitor gets a correct, pinnable image reference in seconds and can trace any published digest back to its PHP version, extension versions, commit and build date.

## Positioning

A matrix of images (PHP 8.2 to 8.6 RC × alpine/trixie × cli/php-fpm/php-fpm-nginx/frankenphp, plus nginx, amd64 + arm64) built from php-src tags, rebuilt daily when upstream inputs or fixable OS CVEs change, signed with cosign, with every upstream input recorded as OCI labels. The site can show per-build provenance because the pipeline records it.

## Operating Context

- Tags follow `<version>-<os>-<variant>` with default components (version → latest stable, os → alpine, variant → cli); `latest` and `unstable` are aliases. Logic lives in `scripts/tags.sh`.
- `versions.json` (the Matrix file) is the source of truth for versions, stability, OS list, extensions, and extensions dropped from 8.6 with reasons.
- CI (`.github/workflows/build.yml`) builds per Lane (version, OS, arch), pushes untagged per-arch images by digest to `php` or `nginx`, and the `merge` job publishes multi-arch manifests from them.
- Published images are never deleted; superseded digests stay pullable. A rebuild in place still moves tags without a tagged trace, so history is recorded at build time.
- Visitors copy references into Dockerfiles; digest pinning (`@sha256:…`) is a real workflow.

## Capabilities and Constraints

- Image list: every published tag and alias, per variant/OS/version.
- Image builder: pick PHP version, OS, variant, architecture → canonical tag, all aliases, digest-pinned reference, `docker pull`/`FROM` snippets, plus the image's build history.
- Feature matrix: extensions × PHP version (including dropped-on-8.6 with reasons), variants × OS, bundled tools (PIE, install-php-extensions; no Composer).
- Changelog: image-level changes derived from recorded build history (PHP, extension, nginx, FrankenPHP, s6, base digest bumps, CVE rebuilds) merged with notable commits on main.
- Build history: the merge job appends a record per published manifest (date, commit, digest, full PHP version, label versions) to a data file on the gh-pages branch.
- Architecture choice only changes the platform-specific digest; tags are multi-arch.
- 8.6 is Unstable/best effort; no 8.6 FrankenPHP.
- Undecided: whether past builds before the site launch get backfilled from currently tagged images.

## Brand Commitments

Terminology from `GLOSSARY.md` is binding: Variant (not type/flavour), OS, Lane, Stable/Unstable, Matrix file, App root, Public path. No existing logo or visual identity.

## Evidence on Hand

- `README.md`: tags, images, configuration, hardening docs.
- `versions.json`, `docker-bake.hcl`, `scripts/tags.sh`: real data for the matrix and tag aliases.
- `docs/decisions/`: ADRs explaining design choices.
- No build history exists yet; it starts accumulating once recording ships. No download counts, users, or testimonials; do not invent them.

## Product Principles

1. The reference is the product: every view ends in something copyable and correct.
2. Derived, never hand-maintained: all site data comes from the Matrix file, tag logic and recorded builds.
3. Provenance over promises: show digests, commits and versions rather than claims.
4. Unstable is labelled as such everywhere it appears.
