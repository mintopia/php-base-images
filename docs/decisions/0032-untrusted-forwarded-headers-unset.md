# Decision: Untrusted forwarded headers are removed, not emptied

Status: accepted
Date: 2026-10-27

## Context
ADR 0008 set `X-Forwarded-Host`, `-Port`, `-Prefix` and `Forwarded` to an empty string when the request wasn't from a Trusted proxy. FrankenPHP passed that empty string to PHP as `HTTP_X_FORWARDED_HOST=""`. Laravel's `trustProxies(at: '*')`, which ADR 0008 says is safe, treats a present header as the host, so the app's host became blank and its URLs became `https:`. nginx already left empty values out with `if_not_empty`.

## Decision
Everything in ADR 0008 still applies, except:
- `X-Forwarded-Host`, `-Port` and `-Prefix` reach PHP only from a Trusted proxy. Otherwise they are absent from `$_SERVER`, not empty.
- `Forwarded` is always absent.
- FrankenPHP removes them with `request_header` before `php_server`, matched on `{http.vars.trusted_proxy}`, instead of `env` overrides. `REMOTE_ADDR`, `HTTPS`, `REQUEST_SCHEME`, `X-Forwarded-For` and `X-Forwarded-Proto` keep their `env` overrides.
- The smoke test fails if any `HTTP_*` value reaching PHP is an empty string, on nginx and FrankenPHP.

## Consequences
- Apps can trust every proxy without the host, port or prefix being blanked.
- nginx and FrankenPHP give PHP the same `$_SERVER` keys.

## Supersedes
0008
