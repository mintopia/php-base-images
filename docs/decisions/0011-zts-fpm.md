# Decision: src builds compile PHP once, ZTS, for every Variant

Status: accepted
Date: 2026-10-22

## Context
ADR 0001 made `cli` ZTS to share FrankenPHP's extension build and kept `php-fpm` NTS, so every src Lane compiled PHP twice (zts, fpm, about 10 minutes each) and built extensions twice. PHP 8.6's FPM is ZTS upstream anyway. The official images have no ZTS FPM before 8.6.

## Decision
- `PHP_SOURCE=src` (the default): `build/php-src.sh` makes one ZTS build with CLI, embed and FPM. The `zts` image copies it without FPM, the `fpm` image copies all of it. `php-fpm` is ZTS on every version and copies its extensions from the single ZTS extension builder (`FPM_EXT_BUILDER=zts`).
- `PHP_SOURCE=upstream`: `php-fpm` stays on `php:<ver>-fpm-<os>`, NTS before 8.6, with its own `ext-builder-nts` (`FPM_EXT_BUILDER=nts`), as in ADR 0001.

## Consequences
- An src Lane compiles PHP and its extensions once; cold builds drop by about 10 minutes per arch.
- php-fpm pays the small ZTS overhead on 8.2–8.5 in src mode. Extensions must be thread-safe in FPM too, which they already were for `cli` and `frankenphp`.
- php-fpm's thread safety differs between src and upstream mode before 8.6; `php -i | grep 'Thread Safety'` tells them apart.

## Supersedes
0001-zts-cli.md
