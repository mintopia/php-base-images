# Decision: Bake builds each Variant from a shared php-src Dockerfile and per-OS Dockerfiles

Status: accepted
Date: 2026-10-24

## Context
Each Variant needs the same compiled PHP, FrankenPHP and extensions, and only the packaging differs between Alpine and Debian. Keeping the compile steps in one place stops the two OSes drifting apart.

## Decision
- `docker-bake.hcl` defines one target per Variant: `cli`, `php-fpm`, `php-fpm-nginx`, `frankenphp` and `nginx`. Each Lane builds the targets for its PHP version and OS.
- `php-src.Dockerfile` holds every PHP stage: the `src` tarball, the `zts`, `fpm` and `zts-frankenphp` bases, the `ext` stage, and the build product stages (ADR 0023).
- `alpine.Dockerfile` and `trixie.Dockerfile` build only the final images. Their PHP inputs come from `php-src.Dockerfile` through bake `contexts` (`target:`).
- Build product stages are `FROM scratch` and hold only their files. A restored product replaces its stage with a named context (ADR 0023).
- Final-stage `COPY` steps use `--link`.
- Bake sets the OCI labels and `net.mintopia.ext.<name>.version` for each Variant.

## Consequences
- A change to `php-src.Dockerfile` affects both OSes. A change to one OS Dockerfile affects only that OS.
- A local build needs `PHP_TAG`, from `scripts/resolve-php-tag.sh`. Without restored products, bake builds each product inline.
- hadolint lints `alpine.Dockerfile`, `trixie.Dockerfile` and `php-src.Dockerfile`.

## Supersedes
None
