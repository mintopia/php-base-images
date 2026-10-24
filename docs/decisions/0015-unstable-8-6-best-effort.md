# Decision: PHP 8.6 is best effort while in RC

Status: accepted
Date: 2026-10-24

## Context
PHP 8.6 is still in RC. Some extensions do not build against it, and fixing them would mean maintaining patches to upstream code.

## Decision
- 8.6 is marked `stable: false`. It builds from the latest RC tag (`scripts/resolve-php-tag.sh --unstable`).
- An extension that fails to build is dropped, not patched. `versions.json` lists it under `dropped` with the failure reason: apcu, grpc, protobuf and redis at present.
- 8.6 has no FrankenPHP image (`frankenphp: false`).
- The `unstable` tag points at the 8.6 cli image on Alpine. Only the version tags and `unstable` are published for 8.6 (ADR 0016).
- An RC is not a patch release and is not maintained once superseded (ADR 0017).

## Consequences
- 8.6 images lack the dropped extensions. Each drop's reason is in `versions.json`.
- When 8.6 becomes stable, its `stable` flag changes, and its tags follow the stable rules.

## Supersedes
None
