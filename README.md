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

PHP 8.6 is best effort while in RC. The build drops extensions that fail to compile and lists them under `dropped` in `versions.json`. There is no 8.6 FrankenPHP image until upstream publishes one.

## What's inside

- Extensions: bcmath, gd, grpc, opcache, opentelemetry, pcntl, pdo, pdo_mysql, pdo_odbc, pdo_pgsql, pdo_sqlite, protobuf, redis, snmp.
- `install-php-extensions` and `pie` for adding extensions. Composer is not included.
- `php.ini-production` installed as `php.ini`. Opcache is on, except in `cli`.
- `cli` and `frankenphp` are ZTS builds. `php-fpm` is NTS.
- The trixie PHP images remove the upstream build toolchain but keep upstream's layers, so they stay large. Use Alpine for small pulls.
- OCI labels record the base image digest and every upstream version in the image.

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

Setting `PUID` creates a user `app` with that UID and runs PHP as it. The group ID is `PGID`, which defaults to `PUID`. The entrypoint doesn't chown anything, so mounts must already be readable by that user.

#### Chaining entrypoints

The entrypoint runs each executable file in `/docker-entrypoint.d/` in filename order, as root, after its own setup and before the container's command. Each hook does its work and then runs `exec "$@"` to pass control to the next one. A hook that doesn't run `exec "$@"` stops the container's command from starting. When `PUID` is set, the switch to `app` happens at the end of the chain, so hooks can still chown or write root-owned files. Each image built on top of another can add its own hook. Hook filenames must not contain spaces.

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
| `PHP_FPM_HOST` | `php-fpm` in `nginx`, `127.0.0.1` in `php-fpm-nginx` |
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
