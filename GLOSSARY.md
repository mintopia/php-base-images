# PHP Base Images

A matrix of PHP container images published to GHCR, replacing mintopia/php-docker and mintopia/php-frankenphp-base.

## Language

**Variant**:
The runtime shape of an image: `cli`, `php-fpm`, `php-fpm-nginx`, `frankenphp`, or `nginx`. Third component of a tag.
_Avoid_: type, flavour, target

**Target**:
The Dockerfile stage that produces one Variant. Build-side name for a Variant.

**OS**:
The base distribution of an image: `alpine` (latest stable) or `trixie` (Debian slim). Second component of a tag.

**Lane**:
One (PHP version, OS, architecture) triple. The unit of CI work: one job builds every Target for a Lane.

**Matrix file**:
The single checked-in file listing supported PHP versions, their stability, their OS list and their extension list. Sole source of truth for what gets built.

**Bundled extension**:
An extension shipped in the PHP source tree (bcmath, pcntl, pdo_*, gd, snmp). Installed with the extension installer script.

**PIE extension**:
An extension distributed via Packagist and installed with PIE (apcu, mongodb, opentelemetry, protobuf, redis). Unofficial Packagist mirrors are acceptable. grpc is the exception: built with phpize against the `libgrpc` build product, which is compiled from the latest grpc release (ADR 0030).

**Stable**:
A PHP minor line with a GA release. Only Stable lines receive the `latest`, `8`, and version-less default tags.

**Unstable**:
A PHP minor line still in RC (currently 8.6). Best effort: extensions that fail to build are dropped, not fixed. Receives the `unstable` tag and its own version tags only.
_Avoid_: develop

**Default tag component**:
The value a tag component takes when omitted: version → latest Stable, OS → `alpine`, Variant → `cli`.

**App root**:
The application's base directory, set by `APP_ROOT` (default `/app`). The container's working directory.

**Public path**:
The directory served over HTTP, set by `APP_PUBLIC_PATH` (default `$APP_ROOT/public`). Shared by nginx, php-fpm and FrankenPHP.
_Avoid_: document root, web root, nginx root

**PUID / PGID**:
Optional runtime UID and GID the processes run as. Omitted means root. No ownership of mounts is changed on the user's behalf.

**Smoke test**:
The per-Target check run in a Lane before anything is pushed.

**Upstream check**:
The daily job that compares published images against upstream (PHP, OS, nginx, FrankenPHP) and scans them for fixable OS-package CVEs, triggering rebuilds for affected Lanes.

**php-src build**:
PHP compiled from a php-src git tag by `php-src.Dockerfile`. Every Lane uses it.

**Build product**:
The files of one slow build step for one PHP tag, OS and arch (`php`, `frankenphp`, `ext-grpc`, `ext-<PIE extension>`), cached as a tarball in the GitHub Actions cache and given to a Lane's bake as a named context. See ADR 0023. `libgrpc` is shared by every PHP tag of an OS and arch (ADR 0030).

**Full rebuild**:
A run with `--all` that rebuilds every Lane regardless of upstream changes: a push that changes an image input, `force`, or a pull request.

**Trusted proxy**:
A proxy or load balancer whose address is in `TRUSTED_PROXIES`. Only requests connecting from one have their forwarded headers believed; see ADR 0008.
