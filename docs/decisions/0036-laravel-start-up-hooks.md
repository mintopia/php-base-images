# Decision: Opt-in Laravel start-up hooks

Status: accepted
Date: 2026-11-23

## Context
Running Laravel on the images took a hand-written start-up hook that created the `storage/` directories and ran `artisan optimize` as PUID. Every app Dockerfile also needed a `chown`, and Octane needed its worker script copied over `public/index.php` in the build. Issue #42 reported that `php artisan octane:frankenphp` replaces the image's start and loses `TRUSTED_PROXIES`, `HTTPS` handling and PUID.

## Decision
- The PHP images ship `/docker-entrypoint.d/20-laravel-optimize`. With `LARAVEL_OPTIMIZE=true` and an `artisan` in the App root, it chowns `storage/` and `bootstrap/cache` to PUID:PGID when anything in them is owned by someone else, creates Laravel's storage directories and runs `php artisan optimize` as PUID. If the chown fails, the container stops with an explanation.
- The FrankenPHP image ships `/docker-entrypoint.d/10-laravel-octane`. With `LARAVEL_OCTANE=true`, it adds a worker to `php_server`, through a new `{$FRANKENPHP_PHP_SERVER_CONFIG}` placeholder in the Caddyfile, that runs `vendor/laravel/octane/bin/frankenphp-worker.php` for every request that isn't a static file. Nothing is written to the app.
- `LARAVEL_OCTANE_WORKERS` sets the worker count. Unset, FrankenPHP starts two per CPU the container may use.
- Both hooks do nothing unless their variable is `true`.

## Consequences
- A Laravel Dockerfile needs only Composer, `COPY` and two variables; every role keeps the image's start.
- `LARAVEL_OPTIMIZE` is the one place the image changes ownership on the user's behalf, limited to the two directories Laravel writes to. It needs `CAP_CHOWN` unless PUID already owns them, as with a tmpfs mounted with `uid=`.
- The ownership check scans every file in those directories, about 10 ms per 10,000 files, more on a Docker Desktop bind mount.
- `LARAVEL_OCTANE` refuses to start alongside a worker in `FRANKENPHP_CONFIG`.
- Under the Octane worker, `SCRIPT_NAME` and `PHP_SELF` are empty; Laravel doesn't use them.
- Laravel-specific code now lives in a framework-neutral image, covered by the smoke test's stand-in app rather than a real Laravel install.

## Supersedes
None
