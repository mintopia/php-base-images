# Decision: PHP 8.6 is Stable, with extensions still dropped

Status: accepted
Date: 2026-11-19

## Context
PHP 8.6.0 is GA. ADR 0015 made 8.6 best effort while in RC. On 8.6.0, no released version of apcu (5.1.28), grpc (1.85.3), protobuf (pie-extensions 35.1) or redis (6.3.0) builds. apcu master and phpredis develop do build, but neither is released. FrankenPHP 1.13.5 and install-php-extensions 2.13.2 support 8.6.

## Decision
- 8.6 is `stable: true` and builds from GA tags. As the newest Stable minor it takes `latest`, `8` and the version-less tags (ADR 0016), and `unstable` (ADR 0033).
- 8.6 has FrankenPHP images.
- apcu, grpc, protobuf and redis stay under `dropped` in `versions.json` until a release builds. Unreleased branches are not used.
- The install-php-extensions patch for unreleased minors is removed; 2.13.2 lists 8.6.
- The next RC line (8.7) follows ADR 0015's best-effort rules.

## Consequences
- `latest` loses apcu, grpc, protobuf and redis. Users who need them pin `8.5`.
- Pull request builds stay on 8.5, which still has every extension.
- Each dropped extension returns when a release builds, by moving it from `dropped` to `extensions`.

## Supersedes
ADR 0015, for 8.6. Its best-effort rules still apply to future RC lines.
