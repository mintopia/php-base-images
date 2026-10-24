# Decision: Trixie images keep the build toolchain out of the runtime

Status: accepted
Date: 2026-10-24

## Context
The Debian images are built on `debian:trixie-slim`. A runtime that installs the PHP build dependencies (`PHPIZE_DEPS`) carries a compiler layer into every image, and purging it in a later step does not remove it from the image.

## Decision
- The `os-trixie` base installs only the runtime basics. The `PHPIZE_DEPS` packages are installed in `builder-trixie`.
- The `PHPIZE_DEPS` variable is still set in the runtime base, so a derived image can run `apt-get install $PHPIZE_DEPS` before `docker-php-ext-install`.
- Final stages install the runtime dependencies listed in `/runtime-deps`, mark them manual, purge `PHPIZE_DEPS` (a no-op in this base, kept as a guard), run `apt-get upgrade`, and clear the setuid and setgid bits on every file.
- Trixie images are layered on `debian:trixie-slim`. They are not flattened.

## Consequences
- The runtime image has no compilers.
- Derived images that compile extensions must install `$PHPIZE_DEPS` first. `install-php-extensions` installs its own build dependencies.
- Setuid and setgid binaries in the base lose the bit. Tools that rely on it, such as `su`, stop working on trixie.

## Supersedes
None
