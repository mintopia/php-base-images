# Decision: One ZTS PHP build serves cli, php-fpm and FrankenPHP

Status: accepted
Date: 2026-10-24

## Context
FrankenPHP requires thread-safe (ZTS) PHP, and its extensions must be built against ZTS. Building PHP once per Variant, or once NTS and once ZTS, doubles the compile time and the extension builds. php-fpm has no official ZTS image before PHP 8.6.

## Decision
- `build/php-src.sh` makes one ZTS build with the CLI, the embed SAPI (`libphp.so`, for FrankenPHP) and FPM.
- The `zts` stage (cli) copies the build without FPM. The `fpm` stage (php-fpm) copies all of it. `zts-frankenphp` takes `libphp.so`.
- php-fpm is ZTS on every PHP version.
- Every extension is built against this one build and serves every Variant.

## Consequences
- A Lane compiles PHP once. Cold builds are about 10 minutes shorter per architecture.
- cli and php-fpm on 8.2 to 8.5 are ZTS, unlike the docker-library NTS images. Check with `php -i | grep 'Thread Safety'`.
- Extensions must be thread-safe. The smoke test loads each one under ZTS.

## Supersedes
None
