# Decision: PHP images leave out the CGI, phpdbg and embed binaries

Status: accepted
Date: 2026-10-24

## Context
Those binaries, `libphp.so` and the man pages add about 70 MB uncompressed to the cli and php-fpm images, and none of these Variants use them. Extension `.so` files need stripping to keep them small.

## Decision
- php-src builds with `--disable-cgi --disable-phpdbg`.
- `libphp.so` (the embed SAPI) is removed from the `zts` and `fpm` images. Only `frankenphp` ships it.
- Man pages are removed.
- Extension `.so` files and the PHP binaries are stripped.
- `/usr/src/php.tar.xz` stays in the images, so `docker-php-source` and `docker-php-ext-install` work in derived images.

## Consequences
- The cli and php-fpm images are about 85 MB smaller uncompressed.
- Anyone who needs `php-cgi`, `phpdbg` or `libphp.so` in cli or php-fpm must build their own image. `phpize`, `php-config` and the headers remain.

## Supersedes
None
