# Decision: The web server resolves the client address and normalises forwarded headers

Status: accepted
Date: 2026-10-24

## Context
Apps behind a proxy need the real client address and scheme. If the web server passes client-sent `X-Forwarded-*` headers through unchanged, any client can spoof them. FrankenPHP takes `REMOTE_ADDR` and `HTTPS` from the raw connection, so Caddy's `trusted_proxies` alone does not reach PHP.

## Decision
- `TRUSTED_PROXIES` (CIDRs) and `CLIENT_IP_HEADER` (default `X-Forwarded-For`) control both nginx and FrankenPHP. The older `NGINX_REAL_IP_FROM` and `NGINX_REAL_IP_HEADER` are still read.
- A request comes from a Trusted proxy when its connecting address is in `TRUSTED_PROXIES`. The client is the rightmost untrusted address in `CLIENT_IP_HEADER`. nginx uses `real_ip_recursive`, and Caddy uses `trusted_proxies_strict`.
- PHP always gets normalised values:
  - `REMOTE_ADDR` is the resolved client.
  - `HTTPS` and `REQUEST_SCHEME` come from `X-Forwarded-Proto` only from a Trusted proxy.
  - `X-Forwarded-For` and `X-Forwarded-Proto` are rewritten to match those values.
  - `X-Forwarded-Host`, `-Port` and `-Prefix` pass through only from a Trusted proxy. Otherwise they are empty.
  - `Forwarded` is always empty.
- FrankenPHP does this with `php_server` `env` overrides, fed by Caddy's `{client_ip}` and `{http.vars.trusted_proxy}`. The Caddy `servers` block is emitted only when `TRUSTED_PROXIES` is set.
- `php-fpm` on its own takes `REMOTE_ADDR` and `HTTPS` from whatever sends it FastCGI, so set `TRUSTED_PROXIES` on that sender.

## Consequences
- Apps need no proxy configuration, and it is safe to trust every proxy.
- Apps that read `X-Forwarded-Host`, `-Port` or `-Prefix` see them empty unless the request came from a Trusted proxy.
- `Forwarded` (RFC 7239) is not parsed. Proxies must send `X-Forwarded-*`, or a single-address header such as `CF-Connecting-IP`.
- FrankenPHP fails to start if `TRUSTED_PROXIES` is set and `CADDY_GLOBAL_OPTIONS` also defines a `servers` block.

## Supersedes
None
