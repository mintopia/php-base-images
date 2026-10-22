# Decision: The web server resolves the client and normalises forwarded headers

Status: accepted
Date: 2026-10-22

## Context
nginx resolved `REMOTE_ADDR` from `NGINX_REAL_IP_FROM` but passed the client's own `X-Forwarded-*` headers to PHP unchanged. Apps that trust every proxy, which is common in containers, could be spoofed. Once `REMOTE_ADDR` is the client, the app no longer sees the load balancer as a proxy, so `X-Forwarded-Proto` was ignored and HTTPS behind a TLS-terminating load balancer went undetected. FrankenPHP 1.13 takes `REMOTE_ADDR` and `HTTPS` from the raw connection, so Caddy's `trusted_proxies` had no effect on PHP.

## Decision
- One setting, `TRUSTED_PROXIES` (CIDRs) plus `CLIENT_IP_HEADER`, drives nginx and FrankenPHP. `NGINX_REAL_IP_FROM` and `NGINX_REAL_IP_HEADER` are still read.
- A request is from a Trusted proxy when its connecting address is in `TRUSTED_PROXIES`. The client is the rightmost untrusted address in `CLIENT_IP_HEADER`: nginx `real_ip_recursive`, Caddy `trusted_proxies_strict`.
- PHP always gets normalised values:
  - `REMOTE_ADDR` is the resolved client.
  - `HTTPS` and `REQUEST_SCHEME` come from `X-Forwarded-Proto` only from a Trusted proxy.
  - `X-Forwarded-For` and `X-Forwarded-Proto` are rewritten to match those values.
  - `X-Forwarded-Host`, `-Port` and `-Prefix` pass through only from a Trusted proxy, otherwise they're blanked.
  - `Forwarded` is always blanked.
- On FrankenPHP, this is done with `php_server` `env` overrides fed by Caddy's `{client_ip}` and `{http.vars.trusted_proxy}`. The Caddy `servers` block is only emitted when `TRUSTED_PROXIES` is set, so an existing block in `CADDY_GLOBAL_OPTIONS` keeps working on its own.

## Consequences
- Apps need no proxy configuration, and trusting every proxy is safe.
- Apps that read `X-Forwarded-Host`, `-Port` or `-Prefix` without a Trusted proxy now see them empty.
- `Forwarded` (RFC 7239) is not parsed; proxies must send `X-Forwarded-*` or a single-address header such as `CF-Connecting-IP`.
- FrankenPHP with both `TRUSTED_PROXIES` and a `servers` block in `CADDY_GLOBAL_OPTIONS` fails to start.
- If FrankenPHP starts honouring Caddy's client IP itself, the `env` overrides become redundant but harmless.

## Supersedes
None
