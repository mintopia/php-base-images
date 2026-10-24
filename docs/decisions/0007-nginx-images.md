# Decision: nginx comes from nginx.org packages, and the combined image runs it under s6-overlay

Status: accepted
Date: 2026-10-24

## Context
The nginx image and the combined php-fpm-nginx image need a current nginx that does not follow the distro's release schedule, and the build tracks its version.

## Decision
- Both OSes install nginx from the nginx.org repository, pinned to `NGINX_VERSION`. Alpine uses the apk repository and trixie uses the apt repository. Each repository's signing key is pinned by checksum.
- `scripts/resolve-matrix.sh` reads the latest nginx.org version for each OS and sets `NGINX_VERSION`. The label `net.mintopia.nginx.version` records it.
- The `nginx` image listens on 8080 and proxies to `PHP_FPM_HOST` (default `php-fpm`) on `PHP_FPM_PORT` (default 9000). Its config comes from `rootfs/nginx`.
- The `php-fpm-nginx` image adds nginx and s6-overlay to the php-fpm image. s6-overlay is pinned by `S6_OVERLAY_VERSION`, tracked from its latest GitHub release, and recorded in `net.mintopia.s6.version`. It runs nginx and php-fpm as services.
- The `nginx` Variant is built only in the lane for the lowest stable PHP version in the Matrix (8.2 on a full run). It is not built for patch lanes. Its tags are `<os>` and, on Alpine, `latest` (ADR 0016).

## Consequences
- An nginx update makes the `nginx` image and every `php-fpm-nginx` image stale through `net.mintopia.nginx.version`, so the daily check rebuilds those, including published older patches. `cli`, `php-fpm` and `frankenphp` are not rebuilt.
- PHP updates do not rebuild the nginx image.
- The nginx image does not depend on the PHP version, so it has one lane per OS and architecture.
- `nginx@nginx~<version>` on Alpine pins the nginx minor line.

## Supersedes
None
