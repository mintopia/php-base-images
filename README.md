# PHP base images

Multi-arch (amd64, arm64) PHP images for Alpine and Debian trixie, published to `ghcr.io/mintopia/php`, with a matching nginx image at `ghcr.io/mintopia/nginx`. They replace `mintopia/php-docker` and `mintopia/php-frankenphp-base`.

## Using the images: [php.mintopia.net](https://php.mintopia.net/)

- [Images](https://php.mintopia.net/images/): pick a PHP version, OS and Variant for the exact tag, what's in it and every build.
- [Usage](https://php.mintopia.net/usage/): compose files for each Variant, proxies, hardening, logs, extending and Xdebug.
- [Matrix](https://php.mintopia.net/matrix/): extensions per PHP version, and which Variants exist on which OS.
- [Changelog](https://php.mintopia.net/changelog/): what changed in each published build.

```dockerfile
FROM ghcr.io/mintopia/php:8.5-php-fpm
```

This README covers the codebase and the [environment variable reference](#configuration). `GLOSSARY.md` defines the project's terms, and `docs/decisions/` records why things are the way they are.

## Repository layout

```
versions.json          # the Matrix file: PHP versions, OSes, extensions, dropped 8.6 extensions
docker-bake.hcl        # build targets per Variant
alpine.Dockerfile      # Alpine images, on php-src or official php images
trixie.Dockerfile      # Debian trixie images
php-src.Dockerfile     # compiles PHP from a php-src tag
build/                 # build-time scripts: extensions, grpc, FrankenPHP, docker-php-* helpers
rootfs/                # files copied into images: entrypoint, nginx, php-fpm, s6, Caddy config
scripts/               # tag logic, matrix resolution, build records
tests/smoke.sh         # smoke-tests a built image
site/                  # the Astro site at php.mintopia.net
.github/workflows/     # build, lint, site
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

- A push to `main` rebuilds and publishes every lane when it changes an image input (Dockerfiles, `docker-bake.hcl`, `versions.json`, `build/`, `rootfs/`, `scripts/tags.sh`). Other pushes run the daily upstream check. The site deploys at the end of every build run. To rebuild after a workflow-only change, run `build` with `force`.
- A daily job rebuilds only the images whose upstream inputs have changed, whose OS packages have CVEs with a fix available, or that were built over 30 days ago. The rest of the lane keeps its published digest. It compares the current PHP, OS, nginx, FrankenPHP, s6-overlay and extension versions against the labels on the published images, and Trivy scans the published SBOM for CVEs. Every CI build upgrades OS packages, so a rebuild ships the fix.
- `workflow_dispatch` with `force` rebuilds everything.
- Older patch releases are still maintained. Once `8.5.12` ships, `8.5.11-*` tags keep getting the same daily rebuilds, built from the `php-8.5.11` source tag. Only the `8.5.11*` tags move.
- Each PHP version builds and merges in its own call of `.github/workflows/lanes.yml`, so one version publishes without waiting for the others.
- Each site build lists every recorded build's CVEs and flags the critical ones. OS package CVEs come from a Trivy scan of the build's SBOM, and PHP CVEs from php-src's security advisories.
- Pull requests build and smoke-test 8.5 amd64 on both OSes without publishing. The `full-build` label builds every lane.
- The workflow signs published manifests with keyless cosign. To verify one: `cosign verify ghcr.io/mintopia/php:8.5 --certificate-identity-regexp 'https://github.com/mintopia/php-base-images/' --certificate-oidc-issuer https://token.actions.githubusercontent.com`.
- Lanes push per-arch images and BuildKit cache to `ghcr.io/mintopia/php-base-images-cache`, and the merge job copies only the finished multi-arch image into `php` or `nginx`. Published images are never deleted, so superseded `@sha256:` digests keep resolving. [php-base-images-cache](https://github.com/mintopia/php-base-images-cache) cleans up the cache package.

### PHP source

CI compiles PHP from the latest php-src tag for each minor version, using RCs for unstable versions, so a release ships as soon as php-src tags it. To build a version on the official `php` images instead, set `"source": "upstream"` on it in `versions.json`, or run the workflow with `php_source: upstream`. `php_source: src` forces compiling from php-src, and `php_source: versions.json` follows the file. Tags are the same either way. See `docs/decisions/0008-php-src-default.md`.

To avoid Docker Hub rate limits, set the optional repo variable `DOCKERHUB_USERNAME` and secret `DOCKERHUB_TOKEN`.

## Site

`site/` is an Astro site, rebuilt and deployed to GitHub Pages after every publish, with an `llms.txt` index for LLM tools. Its data comes from `versions.json`, `scripts/tags.sh`, this README's proxy table and the build records on the `site-data` branch, one JSON file per published manifest. To run it locally:

```
git fetch origin site-data && git worktree add .site-data site-data
cd site && npm ci && npm run dev
```

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
| `TRUSTED_PROXIES`, `CLIENT_IP_HEADER` | see [Client IP and proxies](#client-ip-and-proxies) |
| `NGINX_STATUS_PATH` | unset, which turns it off. Serves nginx's `stub_status` page |
| `PHP_FPM_STATUS_PATH`, `PHP_FPM_PING_PATH` | unset, which turns them off. nginx proxies them to php-fpm |
| `PHP_FPM_STATUS_ALLOW` | `127.0.0.1 ::1`. Space-separated CIDRs allowed to reach every status and ping path |

### FrankenPHP

| Variable | Default |
|---|---|
| `SERVER_NAME` | `:8080`. Setting a hostname turns on Caddy's automatic HTTPS |
| `FRANKENPHP_CONFIG` | unset. Goes inside the `frankenphp` global block, for example `worker ./public/index.php` |
| `CADDY_GLOBAL_OPTIONS` | unset. Caddy global options |
| `CADDY_EXTRA_CONFIG` | unset. Extra top-level Caddyfile config |
| `CADDY_SERVER_EXTRA_DIRECTIVES` | unset. Extra directives in the site block |
| `TRUSTED_PROXIES`, `CLIENT_IP_HEADER` | see [Client IP and proxies](#client-ip-and-proxies) |

FrankenPHP also imports any `*.caddyfile` files in `/etc/frankenphp/Caddyfile.d/`.

### Client IP and proxies

This applies to `nginx`, `php-fpm-nginx` and `frankenphp`. The web server works out the real client and scheme and hands them to PHP, so apps don't need a trusted-proxy setup of their own.

| Variable | Default |
|---|---|
| `TRUSTED_PROXIES` | unset, which trusts nothing. Space-separated CIDRs of the proxies or load balancers in front of the container |
| `CLIENT_IP_HEADER` | `X-Forwarded-For`. The header a trusted proxy puts the client address in |

`NGINX_REAL_IP_FROM` and `NGINX_REAL_IP_HEADER` are still read as older names for these.

The web server accepts forwarded headers only from addresses in `TRUSTED_PROXIES`. The [usage guide](https://php.mintopia.net/usage/#proxies) shows what PHP receives either way.

Common setups:

| In front of the container | Set |
|---|---|
| Nothing; clients connect directly | nothing |
| AWS ALB, or another load balancer in a private network | `TRUSTED_PROXIES=10.0.0.0/16`, the VPC CIDR or the load balancer's subnets |
| Traefik, Caddy or nginx on the same Docker network | `TRUSTED_PROXIES=172.16.0.0/12`, or the network's subnet |
| Kubernetes ingress controller | the pod CIDR, for example `TRUSTED_PROXIES=10.244.0.0/16` |
| Cloudflare, straight to the container | Cloudflare's published IP ranges in `TRUSTED_PROXIES`, and `CLIENT_IP_HEADER=CF-Connecting-IP` |

With several proxies in a chain, such as Cloudflare in front of a load balancer, list every hop's range.

Don't trust `0.0.0.0/0` in production. Anything that can reach the container directly could then claim any address and scheme. The status and ping allowlists check the resolved client address.

`php-fpm` on its own has no HTTP side. It takes `REMOTE_ADDR` and `HTTPS` from whatever sends it FastCGI, such as the `nginx` image, so set `TRUSTED_PROXIES` there.

On FrankenPHP, `TRUSTED_PROXIES` adds a `servers` block to Caddy's global options. If `CADDY_GLOBAL_OPTIONS` already has one, as older versions of this README suggested, Caddy won't start with both. Move the CIDRs into `TRUSTED_PROXIES` and remove the block.
