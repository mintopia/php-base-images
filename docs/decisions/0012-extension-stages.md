# Decision: Each extension builds in its own stage, and the ext stage merges them

Status: accepted
Date: 2026-10-24

## Context
One build step for every extension meant a version bump of any one extension rebuilt all of them, including grpc, which is the slowest.

## Decision
- The `ext-base` stage (from `zts`) installs the build dependencies once.
- Each extension has its own stage on `ext-base`: `build-ext-grpc`, and one per PIE extension (`build-ext-redis`, `build-ext-apcu`, `build-ext-mongodb`, `build-ext-opentelemetry`, `build-ext-protobuf`). They build in parallel.
- Each step writes only its new, stripped `.so` and ini files to `/out/files`, and its runtime dependencies to `/out/deps/<step>`.
- Each product is a `FROM scratch` stage (`ext-grpc`, `ext-<name>`). The `ext` stage merges the bundled files and every product's files.
- The `cli`, `frankenphp` and `php-fpm` images copy `/files` from `ext` and install the merged `/deps`.
- The `EXTENSIONS` build argument selects which steps do work. Unselected steps write nothing.

## Consequences
- A version bump rebuilds only that extension.
- Changing `EXTENSIONS` changes every extension product's cache key, so all of them rebuild (ADR 0023).
- The image stages have more layers, and the extension steps run in parallel.

## Supersedes
None
