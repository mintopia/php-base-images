# PHP base images

Multi-arch (amd64, arm64) PHP images for Alpine and Debian trixie, published to `ghcr.io/mintopia/php`, plus a matching nginx image at `ghcr.io/mintopia/nginx`. Replaces `mintopia/php-docker` and `mintopia/php-frankenphp-base`.

## Tags

`<version>-<os>-<variant>`. Any omitted component takes its default: version → latest stable PHP, os → `alpine`, variant → `cli`.

| Component | Values |
|---|---|
| version | `8`, `8.2`, `8.3`, `8.4`, `8.5`, `8.6`, full `8.5.11`, RC `8.6-rc3` |
| os | `alpine`, `trixie` |
| variant | `cli`, `php-fpm`, `php-fpm-nginx`, `frankenphp` |

Examples: `latest` (8.5 alpine cli), `8.5-trixie`, `trixie-frankenphp`, `8.4-php-fpm`, `unstable` (8.6 RC alpine cli).

`ghcr.io/mintopia/nginx:alpine` (also `latest`) and `ghcr.io/mintopia/nginx:trixie`.

PHP 8.6 is best effort while in RC. Extensions that fail to build are dropped (see `dropped` in `versions.json`). There is no 8.6 FrankenPHP image until upstream publishes one.

## What's inside

- Extensions: bcmath, gd, grpc, opcache, opentelemetry, pcntl, pdo, pdo_mysql, pdo_odbc, pdo_pgsql, pdo_sqlite, protobuf, redis, snmp.
- `install-php-extensions` and `pie` for adding more. No Composer.
- `php.ini-production` as `php.ini`; opcache on (off for `cli`).
- `cli` and `frankenphp` are ZTS. `php-fpm` is NTS.
- Trixie PHP images have the upstream build toolchain removed but keep upstream's layers, so they stay large; use Alpine for small pulls.
- OCI labels record the base image digest and every upstream version baked in.

## Ports

| Variant | Listens |
|---|---|
| php-fpm | `[::]:9000` |
| php-fpm-nginx, frankenphp, nginx | `[::]:8080` |

## Environment

All variants:

| Variable | Default |
|---|---|
| `APP_ROOT` | `/app/public` |
| `PUID`, `PGID` | unset (run as root) |
| `PHP_MEMORY_LIMIT` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `32M` |
| `PHP_POST_MAX_SIZE` | `32M` |
| `PHP_MAX_EXECUTION_TIME` | `30` |

Setting `PUID` creates user `app` with that UID (and `PGID`, default `PUID`) and runs PHP as it. Nothing is chowned; mounts must already be readable by that user.

### Chaining entrypoints

Executable files in `/docker-entrypoint.d/` run after the built-in entrypoint and before the command, in filename order, as root. Each one is an entrypoint in the chain: do its work, then `exec "$@"` to hand on (a hook that doesn't `exec "$@"` stops the container's command from starting). When `PUID` is set, the drop to `app` happens at the end of the chain, so hooks can still chown or write root-owned files. Images built on images can each add their own hook; filenames must not contain spaces.

```dockerfile
FROM ghcr.io/mintopia/php:8.5-php-fpm
COPY --chmod=755 migrate.sh /docker-entrypoint.d/50-migrate
```

```sh
#!/bin/sh
set -e
php /app/artisan migrate --force
exec "$@"
```

php-fpm, php-fpm-nginx:

| Variable | Default |
|---|---|
| `PHP_FPM_PM` | `dynamic` |
| `PHP_FPM_MAX_CHILDREN` | `10` |
| `PHP_FPM_START_SERVERS` | `2` |
| `PHP_FPM_MIN_SPARE_SERVERS` | `1` |
| `PHP_FPM_MAX_SPARE_SERVERS` | `3` |
| `PHP_FPM_MAX_REQUESTS` | `500` |
| `PHP_FPM_REQUEST_TERMINATE_TIMEOUT` | `60` |
| `PHP_FPM_STATUS_PATH` | unset (off) |
| `PHP_FPM_PING_PATH` | unset (off) |

nginx, php-fpm-nginx:

| Variable | Default |
|---|---|
| `PHP_FPM_HOST` | `php-fpm` (nginx), `127.0.0.1` (php-fpm-nginx) |
| `PHP_FPM_PORT` | `9000` |
| `PHP_FPM_STATUS_ALLOW` | `127.0.0.1 ::1` (space-separated CIDRs for the status and ping paths) |

frankenphp: `SERVER_NAME` (default `:8080`), plus upstream `FRANKENPHP_CONFIG`, `CADDY_GLOBAL_OPTIONS`, `CADDY_EXTRA_CONFIG`, `CADDY_SERVER_EXTRA_DIRECTIVES`.

## Building locally

```
PHP_TAG=$(scripts/resolve-php-tag.sh 8.5) docker buildx bake -f docker-bake.hcl -f versions.json   # 8.5 alpine, all targets
PHP_VERSION=8.4 OS=trixie PHP_TAG=$(scripts/resolve-php-tag.sh 8.4) docker buildx bake -f docker-bake.hcl -f versions.json cli
PHP_VERSION=8.6 PHP_TAG=$(scripts/resolve-php-tag.sh 8.6 --unstable) docker buildx bake -f docker-bake.hcl -f versions.json cli
PHP_SOURCE=upstream docker buildx bake -f docker-bake.hcl -f versions.json cli                   # on official php images
tests/smoke.sh php:8.5-alpine-cli cli
```

## CI

- Push to `main`: build and publish every lane.
- Daily: rebuild only lanes whose upstream inputs (PHP, OS, nginx, FrankenPHP, s6-overlay, extensions) changed, judged from the labels on the published images.
- Monthly and `workflow_dispatch` with `force`: rebuild everything.
- Pull requests: build and smoke-test 8.5 amd64 on both OSes (label `full-build` for all lanes), no publish.
- Daily cleanup: untagged images older than a day that no tag references are deleted from GHCR, so superseded `@sha256:` digests stop resolving. Pin tags, not digests. Manual runs of `cleanup` default to dry-run.

### PHP source

PHP is compiled from the latest php-src tag for each minor (RCs for unstable versions), so a release ships as soon as php-src tags it. To build a version on the official `php` images instead, set `"source": "upstream"` on it in `versions.json`, or run the workflow with `php_source: upstream` (`src` forces the default; `versions.json` reads the file). Tags are the same either way. See `docs/decisions/0008-php-src-default.md`.

Optional repo settings: variable `DOCKERHUB_USERNAME` and secret `DOCKERHUB_TOKEN` to avoid Docker Hub rate limits.

Design decisions are in `docs/decisions/`; vocabulary in `GLOSSARY.md`.
