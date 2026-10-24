# Decision: The upstream check rebuilds only stale targets

Status: accepted
Date: 2026-10-23

## Context
ADR 0003 and ADR 0009 mark a whole Lane stale when any of its targets is stale, and the Lane then builds and publishes every target. Since ADR 0015 every publish is permanent and listed on the site, so a FrankenPHP release republished unchanged cli, php-fpm and php-fpm-nginx images for every Lane.

## Decision
- The upstream check judges each target on its own: missing, label drift on any arch, or fixable CVEs.
- A Lane builds and merges only its stale targets. BuildKit still builds the stages they share from the registry cache.
- Every target is CVE-scanned, not just until the first stale one.
- `--all` (image-input pushes, `force`, pull requests) still builds every target. The monthly rebuild is replaced by a per-target age check (ADR 0021).

## Consequences
- An upstream change publishes only the images it affects; unaffected targets keep their digest and tags.
- More CVE scans per daily run: one per target instead of at most one per Lane.
- The build job reads the PHP version from the first PHP target it built, since `cli` may not be among them; an nginx-only Lane records no PHP version.

## Supersedes
The Lane-wide rebuild in ADR 0003 and ADR 0009; their label and CVE checks stand.
