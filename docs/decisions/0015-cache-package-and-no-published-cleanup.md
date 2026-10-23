# Decision: Build intermediates live in a separate cache package; published images are never deleted

Status: accepted
Date: 2026-10-23

## Context
`ghcr.io/mintopia/php` and `nginx` held three kinds of image besides published ones: BuildKit cache refs (`cache-*`, ADR 0002), per-arch images pushed by digest that the merge job copies into the multi-arch index and then orphans, and superseded releases. ADR 0007 deleted all untagged ones daily, which also made superseded release digests stop resolving and left the site listing builds nobody could pull. The cache is about 40 GB of unique layers across 136 refs, about four times the 10 GB Actions cache limit, so moving it into the Actions cache would mean constant eviction.

## Decision
- Build lanes push BuildKit cache and per-arch images by digest to `ghcr.io/mintopia/php-base-images-cache`, a public package. Its linked repository is `php-base-images`, because the first push created it there, and GitHub cannot relink it; `mintopia/php-base-images-cache` holds the cleanup and has admin under the package's Actions access. Cache refs are `<ver>-<os>-<arch>-<variant>`.
- The merge job copies the per-arch images into `php` or `nginx` as the finished multi-arch index with its platform images, attestations and cosign signature. Nothing else is pushed to those packages.
- Nothing in `php` or `nginx` is ever deleted. A published build stays pullable by digest after its tags move on.
- Because every publish is permanent, a push to `main` rebuilds every lane only when it changes an image input (Dockerfiles, `docker-bake.hcl`, `versions.json`, `.dockerignore`, `build/`, `rootfs/`, `scripts/tags.sh`). Other pushes run the upstream check (ADR 0003). The site deploys only at the end of a build run.
- All cleanup runs in the cache repository, on the cache package only: untagged, ghost, partial and orphaned images after a day, and any tag not refreshed in 45 days (the monthly full rebuild refreshes every live tag).

## Consequences
- `php` and `nginx` contain exactly the builds the site lists, and storage grows with every publish. Public GHCR storage is free.
- Digest pinning is safe: superseded digests keep resolving.
- The first build after the switch is cold, because the old `cache-*` refs are not read.
- The cache package must stay public (pull requests read the cache anonymously), and it must grant `php-base-images` write access and `php-base-images-cache` admin access for Actions.
- Merge relies on `docker buildx imagetools create` copying across repositories in the same registry. Copying makes a request per blob, so merges run 6 at a time with retries to stay under GHCR's 2000 requests a minute.
- Workflow-only changes are not exercised on `main` until a rebuild; run `build` with `force` to test one.

## Supersedes
ADR 0002 (cache location only; per-target refs and `mode=max` stand) and ADR 0007
