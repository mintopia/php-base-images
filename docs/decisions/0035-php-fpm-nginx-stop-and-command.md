# Decision: php-fpm-nginx runs s6-overlay as its CMD and stops its services gracefully

Status: accepted
Date: 2026-11-23

## Context
`php-fpm-nginx` had `ENTRYPOINT ["docker-entrypoint.sh", "/init"]`. A changed `command`, such as a queue worker, ran under s6-overlay as root next to nginx and php-fpm, ignored `PUID`, and only got SIGTERM after the services stopped, then SIGKILL 3 seconds later. s6 stopped php-fpm and nginx with SIGTERM, which drops in-flight requests. Every stop took about 3 seconds whatever the stop timeout.

## Decision
- `ENTRYPOINT ["docker-entrypoint.sh"]` and `CMD ["/init"]`, as in the other images. A changed `command` replaces s6-overlay and runs through `run-as` as PID 1.
- The php-fpm and nginx s6-rc services set `down-signal` to `SIGQUIT`, their graceful shutdown. The container's stop timeout bounds the wait.
- `S6_KILL_GRACETIME` and `S6_SERVICES_GRACETIME` keep their defaults. The first is a fixed wait after the services stop, and the second only covers legacy `services.d`.

## Consequences
- Workers, schedulers and one-off jobs need only `command`, as on `php-fpm` and `frankenphp`.
- Running a command next to nginx and php-fpm now needs `command: ["/init", ...]`.
- A stop waits for in-flight requests, up to `PHP_FPM_REQUEST_TERMINATE_TIMEOUT` or the stop timeout.
- A command without a SIGTERM handler is PID 1 and ignores SIGTERM, so it is killed at the stop timeout, as on `php-fpm`.

## Supersedes
None. Extends 0007.
