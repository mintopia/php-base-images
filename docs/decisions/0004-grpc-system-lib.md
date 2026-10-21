# Decision: grpc is built in-tree against the system libgrpc, not via PIE

Status: accepted
Date: 2026-10-21

## Context
Every PIE/PECL grpc package bundles the full C core and compiles for 20-30 minutes per lane. No prebuilt Linux `.so` exists that fits docker-library PHP (Sury/Alpine packages are NTS-only and for other PHP builds). grpc's own repo contains a small PHP extension (`src/php/ext/grpc`) that links against an installed libgrpc and builds in seconds, which the previous php-frankenphp-base image already relied on.

## Decision
grpc is the one extension not installed with PIE. The extension builder installs the distro libgrpc, checks out the grpc tag matching that library version, and builds `src/php/ext/grpc` with phpize. Verified 2026-10-21 on both OSes: the extension builds in about two seconds. Alpine 3.24 (grpc 1.78) works unpatched. Debian trixie (libgrpc 1.51, 2022) needs a one-line sed replacing `zend_exception_get_default()` with `zend_ce_exception` because PHP 8.5 removed the former and grpc's config.m4 compiles with `-Werror`. A newer extension source cannot be used against the 1.51 headers.

## Consequences
- grpc version differs between OSes and follows the distro, not Packagist.
- The grpc source checkout is pinned to the distro library version; mismatches break the build loudly, not at runtime.
- `libgrpc` (Alpine) / `libgrpc29t64` (trixie) becomes a runtime dependency, about 25 MB.
- `-Werror` in grpc's config.m4 means any new PHP deprecation breaks the build loudly; expect further sed patches for PHP 8.6 on trixie.

## Supersedes
None
