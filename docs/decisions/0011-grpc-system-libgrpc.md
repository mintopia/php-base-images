# Decision: grpc builds in-tree against the distro's libgrpc

Status: accepted
Date: 2026-10-24

## Context
PIE and PECL grpc packages bundle the full gRPC C core and take 20 to 30 minutes to compile per Lane. No prebuilt Linux `.so` fits docker-library PHP. grpc's own repository has a small PHP extension (`src/php/ext/grpc`) that links against an installed libgrpc and builds in seconds.

## Decision
- grpc is the only extension not installed with PIE. The `ext-grpc` product installs the distro's `libgrpc-dev`, checks out the grpc source tag that matches that library version (`v<version>`, sparse checkout of `src/php/ext/grpc`), and builds with phpize.
- `build/grpc.sh` asserts the library version equals `GRPC_VERSION`, which `scripts/resolve-matrix.sh` sets from the distro's package index. Alpine is grpc 1.78.1 and trixie is libgrpc 1.51.1 at the time of writing.
- On trixie, a sed replaces `zend_exception_get_default(TSRMLS_C)` with `zend_ce_exception`, because libgrpc 1.51 headers do not match newer PHP. The sed is a no-op when the text is absent.
- The runtime dependency (`libgrpc` on Alpine, `libgrpc29t64` on trixie) is recorded in the product and installed in the images, about 25 MB.

## Consequences
- The grpc version follows each distro, not Packagist, so the two OSes can differ.
- A mismatch between the library and the source checkout fails the build.
- grpc's config.m4 builds with `-Werror`, so any PHP deprecation breaks the build. Expect more sed patches for PHP 8.6 on trixie.
- grpc is dropped on PHP 8.6 (ADR 0015).

## Supersedes
None
