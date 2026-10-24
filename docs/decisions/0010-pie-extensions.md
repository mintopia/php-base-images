# Decision: PIE extensions install with PIE at a tracked upstream version

Status: accepted
Date: 2026-10-24

## Context
Some extensions are not bundled with PHP: apcu, mongodb, opentelemetry, protobuf and redis. They are published on Packagist, and PIE builds them from source. Their versions change upstream, so each build needs a record of which version it holds (ADR 0021).

## Decision
- apcu, mongodb, opentelemetry, protobuf and redis are installed with PIE (`ghcr.io/php/pie`, pinned by `PIE_VERSION`), from their Packagist packages. Unofficial Packagist mirrors are acceptable.
- `scripts/resolve-matrix.sh` sets each version to the latest stable release on Packagist, and each is recorded in `net.mintopia.ext.<name>.version`.
- redis is built without the igbinary serializer (ADR 0013).
- mongodb is built with OpenSSL available, so TLS connections work, including MongoDB Atlas.
- An extension that fails to build on a PHP version is listed under `dropped` in `versions.json` with the reason, not patched (ADR 0015).
- grpc is not installed with PIE (ADR 0011).

## Consequences
- A new upstream release rebuilds the affected Lanes through the image labels.
- PIE's own version is resolved from its latest GitHub release. A new PIE release rebuilds the extension products.
- Packagist is queried on every resolve, so a Packagist outage stops the run, and nothing is rebuilt wrongly (ADR 0021).

## Supersedes
None
