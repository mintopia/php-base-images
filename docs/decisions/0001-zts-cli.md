# Decision: CLI images are ZTS to share the FrankenPHP extension build

Status: accepted
Date: 2026-10-21

## Context
FrankenPHP requires thread-safe (ZTS) PHP, so its extensions must be compiled against `php:*-zts-*`. The upstream `php:*-cli-*` image is NTS. php-fpm has no official ZTS image. Building extensions three times per lane (NTS cli, NTS fpm, ZTS frankenphp) doubles build time and cache size.

## Decision
`cli` builds from `php:<ver>-zts-<os>` and shares one ZTS extension builder with `frankenphp`. `php-fpm` builds from `php:<ver>-fpm-<os>` (NTS) with its own NTS extension builder. Two builders per lane, not three.

## Consequences
- CLI differs from upstream default (ZTS vs NTS). Minor runtime overhead; pcntl/parallel-style workloads behave as upstream ZTS.
- grpc has reported ZTS instability; smoke tests must load it under ZTS.
- Swapping CLI back to NTS later only costs a third builder stage.

## Supersedes
None
