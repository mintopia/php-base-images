# PHP base images

Multi-arch (amd64, arm64) PHP images for Alpine and Debian trixie, published to `ghcr.io/mintopia/php`, with a matching nginx image at `ghcr.io/mintopia/nginx`. They replace `mintopia/php-docker` and `mintopia/php-frankenphp-base`.

## Tags

Tags take the form `<version>-<os>-<variant>`. An omitted component takes its default, which is the latest stable PHP for version, `alpine` for os, and `cli` for variant.

| Component | Values |
|---|---|
| version | `8`, `8.2`, `8.3`, `8.4`, `8.5`, `8.6`, full `8.5.11`, RC `8.6-rc3` |
| os | `alpine`, `trixie` |
| variant | `cli`, `php-fpm`, `php-fpm-nginx`, `frankenphp` |

`latest` is 8.5 alpine cli, and `unstable` is the 8.6 RC on alpine cli. Other examples are `8.5-trixie`, `trixie-frankenphp` and `8.4-php-fpm`.

The nginx image is `ghcr.io/mintopia/nginx:alpine`, also tagged `latest`, and `ghcr.io/mintopia/nginx:trixie`.

## Images

Every image is built for `linux/amd64` and `linux/arm64`. `<v>` is a minor (`8.5`), full (`8.5.12`) or RC (`8.6-rc4`) version. For the latest stable minor, 8.5, `<v>` can also be `8` or left out, as in `trixie-frankenphp` or `php-fpm`.

| Image | Variant | OS | Tag | Also tagged | PHP |
|---|---|---|---|---|---|
| `ghcr.io/mintopia/php` | `cli` | alpine | `<v>-alpine-cli` | `<v>-alpine`, `<v>-cli`, `<v>`, `latest` (8.5), `unstable` (8.6) | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `cli` | trixie | `<v>-trixie-cli` | `<v>-trixie` | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `php-fpm` | alpine | `<v>-alpine-php-fpm` | `<v>-php-fpm` | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `php-fpm` | trixie | `<v>-trixie-php-fpm` | | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `php-fpm-nginx` | alpine | `<v>-alpine-php-fpm-nginx` | `<v>-php-fpm-nginx` | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `php-fpm-nginx` | trixie | `<v>-trixie-php-fpm-nginx` | | 8.2, 8.3, 8.4, 8.5, 8.6 RC |
| `ghcr.io/mintopia/php` | `frankenphp` | alpine | `<v>-alpine-frankenphp` | `<v>-frankenphp` | 8.2, 8.3, 8.4, 8.5 |
| `ghcr.io/mintopia/php` | `frankenphp` | trixie | `<v>-trixie-frankenphp` | | 8.2, 8.3, 8.4, 8.5 |
| `ghcr.io/mintopia/nginx` | `nginx` | alpine | `alpine` | `latest` | |
| `ghcr.io/mintopia/nginx` | `nginx` | trixie | `trixie` | | |

PHP 8.6 is best effort while in RC. The build drops extensions that fail to compile and lists them under `dropped` in `versions.json`. There is no 8.6 FrankenPHP image until upstream publishes one.

## What's inside

- Extensions: bcmath, gd, grpc, mbstring, opcache, opentelemetry, pcntl, pdo, pdo_mysql, pdo_odbc, pdo_pgsql, pdo_sqlite, protobuf, redis, snmp.
- `install-php-extensions` and `pie` for adding extensions. Composer is not included.
- `php.ini-production` installed as `php.ini`, with `expose_php` off. Opcache is on, except in `cli`.
- Every Variant is a ZTS build. Images built with `PHP_SOURCE=upstream` have an NTS `php-fpm` before 8.6.
- The trixie images have no build toolchain. `$PHPIZE_DEPS` names it for derived images, and setuid/setgid bits are stripped.
- OCI labels record the source repo, commit, version, base image digest and every upstream version in the image.
- Published manifests are signed with cosign keyless signing. To verify one: `cosign verify ghcr.io/mintopia/php:8.5 --certificate-identity-regexp 'https://github.com/mintopia/php-base-images/' --certificate-oidc-issuer https://token.actions.githubusercontent.com`.

## Configuration

The images read all settings from environment variables when the container starts.

| Variant | Sections | Listens on |
|---|---|---|
| `cli` | [Common](#common) | nothing |
| `php-fpm` | [Common](#common), [php-fpm](#php-fpm) | `[::]:9000`, or `0.0.0.0:9000` without IPv6 |
| `nginx` | [nginx](#nginx) | `0.0.0.0:8080` and `[::]:8080`, or IPv4 only without IPv6 |
| `php-fpm-nginx` | [Common](#common), [php-fpm](#php-fpm), [nginx](#nginx) | the same as `nginx`, plus php-fpm on `9000` |
| `frankenphp` | [Common](#common), [FrankenPHP](#frankenphp) | `:8080`, plain HTTP |

### Common

| Variable | Default |
|---|---|
| `APP_ROOT` | `/app`, the working directory |
| `APP_PUBLIC_PATH` | `$APP_ROOT/public`, served by nginx and FrankenPHP |
| `PUID`, `PGID` | unset, so processes run as root |
| `PHP_MEMORY_LIMIT` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `32M` |
| `PHP_POST_MAX_SIZE` | `32M` |
| `PHP_MAX_EXECUTION_TIME` | `30` |
| `PHP_INI_MODE` | `production`. `development` loads `php.ini-development` instead. Anything else stops the container |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `1`. Set `0` in production for speed, but code changes then need a restart |
| `PHP_SESSION_COOKIE_HTTPONLY` | empty, which is off, as in `php.ini-production` |
| `PHP_SESSION_USE_STRICT_MODE` | `0` |
| `PHP_SESSION_COOKIE_SAMESITE` | empty, which sends no `SameSite` attribute |

Setting `PUID` runs the container's processes with that UID. The group ID is `PGID`, which defaults to `PUID`. The IDs are applied numerically, so no user is added to `/etc/passwd`. php-fpm's master stays root and runs its workers as `PUID`. The entrypoint doesn't chown anything, so mounts must already be readable by that user.

#### Chaining entrypoints

The entrypoint runs each executable file in `/docker-entrypoint.d/` in filename order, as root, after its own setup and before the container's command. Each hook does its work and then runs `exec "$@"` to pass control to the next one. A hook that doesn't run `exec "$@"` stops the container's command from starting. When `PUID` is set, the switch to that user happens at the end of the chain, so hooks can still chown or write root-owned files. Each image built on top of another can add its own hook. Hook filenames must not contain spaces.

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

### php-fpm

These settings apply to `php-fpm` and `php-fpm-nginx`.

| Variable | Default |
|---|---|
| `PHP_FPM_PM` | `dynamic` |
| `PHP_FPM_MAX_CHILDREN` | `10` |
| `PHP_FPM_START_SERVERS` | `2` |
| `PHP_FPM_MIN_SPARE_SERVERS` | `1` |
| `PHP_FPM_MAX_SPARE_SERVERS` | `3` |
| `PHP_FPM_MAX_REQUESTS` | `500` |
| `PHP_FPM_REQUEST_TERMINATE_TIMEOUT` | `60` |
| `PHP_FPM_STATUS_PATH` | unset, which turns it off |
| `PHP_FPM_PING_PATH` | unset, which turns it off |

php-fpm answers the status and ping paths over FastCGI. In `php-fpm-nginx`, nginx publishes them over HTTP to the addresses in `PHP_FPM_STATUS_ALLOW`. With the separate `nginx` image, set the same paths on both containers.

### nginx

These settings apply to the `nginx` image (`ghcr.io/mintopia/nginx`) and to `php-fpm-nginx`.

| Variable | Default |
|---|---|
| `APP_ROOT`, `APP_PUBLIC_PATH` | as in [Common](#common). nginx serves `APP_PUBLIC_PATH` |
| `PHP_POST_MAX_SIZE` | `32M`, used as nginx's `client_max_body_size` |
| `PHP_FPM_HOST` | `php-fpm` in `nginx`, `127.0.0.1` in `php-fpm-nginx`. Re-resolved every 10s via the nameservers in `/etc/resolv.conf`, which ignores search domains, so use a FQDN on Kubernetes |
| `PHP_FPM_PORT` | `9000` |
| `NGINX_REAL_IP_FROM` | unset, which turns it off. Space-separated CIDRs of trusted proxies |
| `NGINX_REAL_IP_HEADER` | `X-Forwarded-For` |
| `NGINX_STATUS_PATH` | unset, which turns it off. Serves nginx's `stub_status` page |
| `PHP_FPM_STATUS_PATH`, `PHP_FPM_PING_PATH` | unset, which turns them off. nginx proxies them to php-fpm |
| `PHP_FPM_STATUS_ALLOW` | `127.0.0.1 ::1`. Space-separated CIDRs allowed to reach every status and ping path |

#### Behind a proxy

Without `NGINX_REAL_IP_FROM`, PHP gets the address of whatever connected to nginx as `REMOTE_ADDR`. Behind a load balancer, that is the load balancer rather than the user. Set `NGINX_REAL_IP_FROM` on the nginx container to the proxy's CIDRs. For users who reach nginx and php-fpm through an AWS ALB:

```
NGINX_REAL_IP_FROM=10.0.0.0/16   # VPC CIDR or ALB subnets
```

nginx then takes the rightmost untrusted `X-Forwarded-For` entry as the client and passes it to php-fpm as `REMOTE_ADDR`. php-fpm needs no change. The status allowlist also checks this client address. Don't trust `0.0.0.0/0` in production, because anything that reaches the container directly could then spoof its address.

### FrankenPHP

| Variable | Default |
|---|---|
| `SERVER_NAME` | `:8080`. Setting a hostname turns on Caddy's automatic HTTPS |
| `FRANKENPHP_CONFIG` | unset. Goes inside the `frankenphp` global block, for example `worker ./public/index.php` |
| `CADDY_GLOBAL_OPTIONS` | unset. Caddy global options |
| `CADDY_EXTRA_CONFIG` | unset. Extra top-level Caddyfile config |
| `CADDY_SERVER_EXTRA_DIRECTIVES` | unset. Extra directives in the site block |

FrankenPHP also imports any `*.caddyfile` files in `/etc/frankenphp/Caddyfile.d/`.

To trust a proxy, set Caddy's `trusted_proxies`. Caddy rejects a block written on one line, so spread it over several lines:

```yaml
environment:
  CADDY_GLOBAL_OPTIONS: |
    servers {
      trusted_proxies static 10.0.0.0/16
    }
```

## Hardening

Every image can run with a read-only root filesystem and no capabilities. Mount writable tmpfs where the Variant needs it. When `PUID` is set, add back `SETUID` and `SETGID` to switch user, and `CHOWN` so that it can write to `/dev/stdout`, which nginx needs:

| Variant | tmpfs |
|---|---|
| `cli` | none, or `/tmp` if the app writes temp files |
| `php-fpm` | `/run`, and `/tmp` for sessions and uploads |
| `nginx` | `/run` |
| `php-fpm-nginx` | `/run:exec`, for s6-overlay, and `/tmp` |
| `frankenphp` | `/data`, `/config`, `/tmp` |

```
docker run --read-only --tmpfs /run:exec --tmpfs /tmp \
  --cap-drop ALL --cap-add SETUID --cap-add SETGID --cap-add CHOWN \
  -e PUID=1000 ghcr.io/mintopia/php:8.5-php-fpm-nginx
```

nginx renders its config into `/run/nginx` at start, so `/etc` stays read-only. Extra `*.conf` files mounted into `/etc/nginx/conf.d/` are still included in the `http` block. FrankenPHP keeps Caddy's state in `/data` and `/config`, so with automatic HTTPS, use a volume rather than tmpfs for `/data` to keep certificates across restarts.

nginx denies requests for dotfiles, such as `/.env` or `/.git/config`, except under `/.well-known/`.

## Development

Set `PHP_INI_MODE=development` for `php.ini-development`, which turns on error display among other things. Leave `PHP_OPCACHE_VALIDATE_TIMESTAMPS` at `1` so that code changes are picked up.

### Xdebug

Install Xdebug, or any other extension, in a derived image with `install-php-extensions`. On Alpine it fetches and removes its own build deps:

```dockerfile
FROM ghcr.io/mintopia/php:8.5-php-fpm
RUN install-php-extensions xdebug
```

On trixie the images have no compiler, so install `$PHPIZE_DEPS` and purge it in the same `RUN`:

```dockerfile
FROM ghcr.io/mintopia/php:8.5-trixie-php-fpm
RUN apt-get update \
    && apt-get install -y --no-install-recommends $PHPIZE_DEPS \
    && install-php-extensions xdebug \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS \
    && rm -rf /var/lib/apt/lists/*
```

Xdebug doesn't support PHP 8.6 yet, and `install-php-extensions` refuses 8.6 until it is released.

Xdebug has no release for PHP 8.6 yet. On 8.6, which has no PEAR, `install-php-extensions` can't fetch PECL extensions, so use `pie install <vendor>/<package>` for those that support 8.6, adding `unzip` alongside `$PHPIZE_DEPS`.

Configure it with `PHP_INI_SCAN_DIR` or a file in `/usr/local/etc/php/conf.d/`, for example `xdebug.mode=debug` and `xdebug.client_host=host.docker.internal`.

### One request per worker

For php-fpm, `PHP_FPM_MAX_REQUESTS=1` restarts each worker after every request, so state can't leak between requests.

FrankenPHP has no per-worker request limit. In development, either don't use worker mode, or let the app restart its worker: Laravel Octane takes `--max-requests=1`, and the Symfony runtime reads `FRANKENPHP_LOOP_MAX=1`.

### Reloading FrankenPHP workers on file changes

FrankenPHP restarts worker scripts when files they match change. Spread the worker block over several lines:

```yaml
environment:
  FRANKENPHP_CONFIG: |
    worker {
      file ./public/index.php
      watch ./**/*.php
    }
```

## Building locally

```
PHP_TAG=$(scripts/resolve-php-tag.sh 8.5) docker buildx bake -f docker-bake.hcl -f versions.json   # 8.5 alpine, all targets
PHP_VERSION=8.4 OS=trixie PHP_TAG=$(scripts/resolve-php-tag.sh 8.4) docker buildx bake -f docker-bake.hcl -f versions.json cli
PHP_VERSION=8.6 PHP_TAG=$(scripts/resolve-php-tag.sh 8.6 --unstable) docker buildx bake -f docker-bake.hcl -f versions.json cli
PHP_SOURCE=upstream docker buildx bake -f docker-bake.hcl -f versions.json cli                   # on official php images
tests/smoke.sh php:8.5-alpine-cli cli
```

## CI

- A push to `main` builds and publishes every lane.
- A daily job rebuilds a lane when one of its upstream inputs has changed or when its OS packages have CVEs with a fix available. It compares the current PHP, OS, nginx, FrankenPHP, s6-overlay and extension versions against the labels on the published images, and Trivy scans the published SBOM for CVEs. Every CI build upgrades OS packages, so a rebuild ships the fix.
- A monthly job rebuilds everything, as does `workflow_dispatch` with `force`.
- Pull requests build and smoke-test 8.5 amd64 on both OSes without publishing. The `full-build` label builds every lane.
- A daily cleanup deletes untagged images that are more than a day old and that no tag references. Superseded `@sha256:` digests then stop resolving, so pin tags rather than digests. Manual runs of `cleanup` default to a dry run.

### PHP source

CI compiles PHP from the latest php-src tag for each minor version, using RCs for unstable versions, so a release ships as soon as php-src tags it. To build a version on the official `php` images instead, set `"source": "upstream"` on it in `versions.json`, or run the workflow with `php_source: upstream`. `php_source: src` forces compiling from php-src, and `php_source: versions.json` follows the file. Tags are the same either way. See `docs/decisions/0008-php-src-default.md`.

To avoid Docker Hub rate limits, set the optional repo variable `DOCKERHUB_USERNAME` and secret `DOCKERHUB_TOKEN`.

Design decisions are in `docs/decisions/`, and `GLOSSARY.md` defines the project's terms.
