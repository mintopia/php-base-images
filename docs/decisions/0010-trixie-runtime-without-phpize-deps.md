# Decision: Trixie src images keep the build toolchain out of the runtime base

Status: accepted
Date: 2026-10-22

## Context
ADR 0005 kept trixie images layered on the upstream `php` base, whose layers carry `PHPIZE_DEPS`, so purging them reclaimed nothing. Since ADR 0008 the default base is our own `php-src.Dockerfile`, which copied that upstream behaviour: `os-trixie` installed `PHPIZE_DEPS` and every final stage purged them again. On `8.5-trixie-cli` that dead layer was 117 MB of 205 MB compressed.

## Decision
`os-trixie` installs only the runtime basics; `PHPIZE_DEPS` move to `builder-trixie`. The `PHPIZE_DEPS` variable stays defined in the runtime base so extension builders and derived images can `apt-get install $PHPIZE_DEPS`. Final stages still purge `PHPIZE_DEPS`, which is a no-op in src mode and still strips the compilers in upstream mode.

## Consequences
- Trixie src images lose the toolchain layer; upstream-mode trixie images are unchanged.
- `docker-php-ext-install` in a derived image needs `apt-get install $PHPIZE_DEPS` first, as it already did after the purge. `install-php-extensions` installs its own build deps.
- Flattening (rejected in 0005) is still unnecessary.

## Supersedes
0005-flatten-trixie-images.md
