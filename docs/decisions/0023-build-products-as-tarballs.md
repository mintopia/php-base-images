# Decision: Slow build steps are build products, cached as tarballs in the GitHub Actions cache

Status: accepted
Date: 2026-10-24

## Context
Only a few steps in a Lane are slow: compiling PHP, building FrankenPHP (Go), building grpc, and building PIE extensions. Their outputs are small file trees. Everything else is package installs and copies that take seconds. Caching whole image layers in a registry produced many cache refs, which needed their own cleanup, and inflated pull counts on the packages.

## Decision
- Four build products exist for each PHP tag, OS and architecture (a leg): `php`, `frankenphp`, `ext-grpc` and `ext-<PIE extension>` for each PIE extension in the version's list.
  - `php`: the PHP install tree, its source tarball and runtime dependencies.
  - `frankenphp`: the binary and libwatcher.
  - `ext-grpc` and `ext-<name>`: each extension's `.so`, ini files and runtime dependencies.
- Each is a `FROM scratch` stage in `php-src.Dockerfile` that holds only its files (ADR 0012).
- `actions/cache` saves each product under an exact key from `scripts/product-keys.sh`. Every key starts with `<tag>-<os>-<arch>-<product>-`, so one lookup lists a leg's entries. The key hash covers:
  - `php`: the PHP tag, OS, arch, OS base digest, `php-src.Dockerfile`, `build/php-src.sh` and `build/docker-php/*`.
  - `frankenphp`: the `php` key, the FrankenPHP version and tarball checksum, the Go and watcher versions, and `build/frankenphp-src.sh`.
  - `ext-grpc`: the `php` key, the grpc version, `EXTENSIONS`, `build/extensions.sh` and `build/grpc.sh`.
  - `ext-<name>`: the `php` key, the extension version, the PIE version, `EXTENSIONS` and `build/extensions.sh`.
- Bake receives each restored product as a local-directory named context (`PRODUCTS`, `PRODUCTS_DIR`). A named context replaces the stage of the same name. A product that is not restored is built inline.
- There is no BuildKit cache import or export anywhere, in the registry or the Actions cache.

## Consequences
- A Lane with every product cached takes about 1 to 2 minutes. A cold Lane takes about 10 to 18 minutes, most of it building products.
- A change to `php-src.Dockerfile`, `build/php-src.sh` or the PHP tag rebuilds every product of the affected legs. A change to an OS Dockerfile rebuilds no product.
- Products are 43 to 53 MB per Lane, compressed, and about 33 MB for 8.6. That is about 0.9 GB for the 20 current Lanes, and about 1.7 GB with older patch Lanes built in the last week. The Actions cache limit is 10 GB, and a repository that goes over it pays for more, or entries are evicted and Lanes go cold.
- GitHub allows 200 new cache entries per minute per repository. A cold start creates about 140 entries, or about 270 with older patch Lanes, across the product builds, so a burst can fail a save, and the next run retries it.
- Local builds need nothing new.

## Supersedes
None
