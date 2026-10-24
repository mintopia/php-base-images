# Decision: Cache build products as tarballs in the GitHub Actions cache

Status: accepted
Date: 2026-10-24

## Context
The BuildKit registry cache (ADR 0002, moved to `ghcr.io/mintopia/php-base-images-cache` by ADR 0015) uses image layers as a cache. Every lane pulled up to eight `mode=max` cache refs on every run, which inflated the package's pull counts and made them useless as a usage signal, and the package filled with refs, per-arch images and orphans that needed a cleanup repository of their own. Only a few steps are slow: compiling PHP, building FrankenPHP (Go), grpc and the PIE extensions. Their outputs are small file trees; everything else in a lane is package installs and copies that take seconds.

The `upstream` PHP source (ADR 0006, ADR 0008) was kept as an opt-out, but nothing uses it, and its nts extension builder and digest lookups doubled the bake and resolve logic.

## Decision
- PHP is always built from php-src. `PHP_SOURCE`, the `php_source` dispatch input, `resolve-matrix.sh --source` and the nts extension builder are gone. Images keep the `net.mintopia.php.source=php-src` label.
- There is no BuildKit cache import or export anywhere.
- **Build products**: `php` (the PHP install tree, tarball and runtime deps), `frankenphp` (binary and libwatcher), `ext-grpc` and `ext-<pie extension>` (each extension's `.so`, ini and runtime deps) are `FROM scratch` stages in `php-src.Dockerfile` that hold only their files. The images consume them only through `COPY --from` and bind mounts. `ext-bundled` is not a product: on php-src builds it compiles nothing and takes a few seconds.
- Bake gives each restored product to the stage of the same name as a local-dir named context (`PRODUCTS`, `PRODUCTS_DIR`); a named context replaces the stage. Without one, the lane builds the stage itself. The OS Dockerfiles build only the final images, on `zts`, `fpm`, `zts-frankenphp` and `ext`, which are `target:` contexts on `php-src.Dockerfile`.
- Products are saved with `actions/cache` under exact keys from `scripts/product-keys.sh`, one set per PHP tag, OS and arch (a leg). Every key starts with `<tag>-<os>-<arch>-<product>-`, so one API call lists a leg's entries:
  - `php`: PHP tag, OS, arch, OS base image digest, `php-src.Dockerfile`, `build/php-src.sh`, `build/docker-php/*`.
  - `frankenphp`: the php key, FrankenPHP version and tarball checksum, Go and watcher versions, `build/frankenphp-src.sh`.
  - `ext-grpc`: the php key, grpc version, `EXTENSIONS`, `build/extensions.sh`, `build/grpc.sh`.
  - `ext-<pie>`: the php key, extension version, PIE version (now pinned, resolved daily), `EXTENSIONS`, `build/extensions.sh`.
- A `products` job in `lanes.yml` runs before the lanes, on native runners, on every non-PR run on `main`, for the current patch of every `versions.json` version on both OSes and arches, stale or not, and for older patch lanes only when they are planned to build in that run. Idle older patches' products may be evicted; their next build rebuilds them. `scripts/product-plan.sh` lists a leg's entries with one `gh api repos/{repo}/actions/caches?key=<leg prefix>` call and matches exact keys locally: missing or created over 30 days ago, it deletes the old entry and builds and saves the product; last used 5 or more days ago, it restores it so the 7-day eviction never reaches it; otherwise nothing. When `php` is rebuilt, every other product of the leg is deleted and rebuilt with it, so no product is ever built against an older php. Building any other product restores `php` first. Filtered dispatches (`php_version`, `os`) only cover what they select.
- Pull requests skip the products job. Their lanes restore what main saved and build anything missing inline, without saving. So does every lane when a product is missing.
- Lanes push untagged per-arch images by digest straight into `ghcr.io/mintopia/php` (or `nginx`). Merge makes the multi-arch index from those same-repository digests, and as its last step deletes each per-arch index it consumed. It never deletes their platform images or attestations: the multi-arch index references them and GHCR does not cascade. Nothing else in `php` or `nginx` is ever deleted, and published digests keep resolving.
- From ADR 0015 these stand: a push to `main` rebuilds every lane only when it changes an image input; merges run 2 at a time per PHP version (ADR 0019).

## Consequences
- A lane with all products cached builds in about 3–5 minutes (package installs, copies, push). A cold lane takes about 30 minutes; locally (arm64, 12 cores) all products for one lane build in about 3 minutes and the lane bake with them in 15–30 seconds against about 3 minutes without.
- A change to `php-src.Dockerfile`, `build/php-src.sh` or a PHP tag rebuilds every product for the affected lanes. Changes to the OS Dockerfiles rebuild no product.
- Product sizes measured for 8.5 alpine and trixie arm64 (zstd tarballs, both alike): php 27 MB, frankenphp 18 MB, extensions 1.5 MB together, about 47 MB a lane, so about 1.7 GB for the 36 current lanes plus any older patch lanes built in the last week, plus up to a second copy for a lane whose products are being replaced. That fits the free 10 GB Actions cache; if it outgrows it, the repository's cache size limit must be raised (billed at $0.07/GiB-month over 10 GB), or entries are evicted and lanes go cold.
- GitHub allows 200 new cache entries per minute per repository. A cold start for every lane creates about 300, spread over the product builds; a burst over the limit fails the save and the next run retries it.
- The products job makes one cache API call per leg (about 40 a run), plus one delete per replaced entry. Merge lists package versions until it reaches ones older than the run, retrying page 1 for listing lag, and a failed lookup or delete only warns.
- The products job needs `actions: write` to delete cache entries. Merge needs the repository to have admin access to `php` and `nginx` to delete per-arch indexes.
- A failed or abandoned run leaves its untagged per-arch indexes in `php` or `nginx`, with their platform images and attestations: a lane that fails its smoke test after pushing, or a merge that fails before its last step. They are orphans no tag points at; nothing cleans them up.
- `ghcr.io/mintopia/php-base-images-cache` and the `php-base-images-cache` repository are no longer used.
- Local builds need nothing new: with no `PRODUCTS`, bake builds every product inline.

## Supersedes
0008-php-src-default.md and 0015-cache-package-and-no-published-cleanup.md. Also the `upstream` source parts of 0011 and 0022, and 0022's push to the cache package.
