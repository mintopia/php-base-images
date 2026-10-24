# Decision: Bundled extensions ship in every image that builds them

Status: accepted
Date: 2026-10-24

## Context
Most PHP applications need extensions beyond the basics. intl is required by frameworks such as Filament and used by Laravel and Symfony. Without these extensions, derived images need a compiler stage, which the trixie runtime does not carry (ADR 0004).

A measured spike on 8.5 cli (arm64) put the cost at about +20% compressed on Alpine and +16% on trixie. Most of it is ICU, about 36 MB uncompressed on each OS.

## Decision
- Every PHP version ships the PHP-source extensions in its `versions.json` list: bcmath, exif, gd, gmp, intl, mbstring, opcache, pcntl, the pdo drivers (pdo, pdo_mysql, pdo_odbc, pdo_pgsql, pdo_sqlite), snmp, soap, sockets and zip. PIE extensions are in ADR 0010.
- intl, zip, exif, sockets, gmp and soap are shared extensions built in the `php-src` configure step. `ext-bundled` installs the rest with `install-php-extensions`. On php-src builds this step is cheap, because the build already provides them.
- Alpine installs `icu-data-full`, because `icu-libs` has English locale data only and intl would fall back to it.

## Consequences
- Common frameworks run without a derived image. `install-php-extensions` and PIE remain for anything else.
- Images are 16 to 20% larger compressed, almost all of it ICU.
- Removing a bundled extension later breaks users who depend on it.

## Supersedes
None
