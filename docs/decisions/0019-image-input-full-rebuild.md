# Decision: A change to an image input rebuilds every Lane

Status: accepted
Date: 2026-10-24

## Context
Every publish is permanent and appears on the site (ADR 0026, ADR 0027). A push that changes how images are built should rebuild every target, not only the ones whose upstream inputs moved. Other pushes do not change the images, so they should not rebuild them.

## Decision
- A push to `main` that changes an image input runs a full rebuild (`--all`). Image inputs are the top-level `*.Dockerfile` files, `docker-bake.hcl`, `versions.json`, `.dockerignore`, `build/`, `rootfs/` and `scripts/tags.sh`. If the changed-files lookup fails, the run is a full rebuild too.
- Any other push to `main` runs the daily upstream check (ADR 0022).
- `workflow_dispatch` with `force` runs `--all`. Its `php_version` and `os` inputs narrow the run.
- A pull request runs `--all --no-patches`, but only PHP 8.5 on amd64 unless it has the `full-build` label.
- The daily cron runs at 04:17 UTC and uses the upstream check.
- A workflow-only change does not rebuild anything. Run `build` with `force` to test it.

## Consequences
- An image input change publishes every target of every current Lane, and each one is a new permanent build.
- Workflow changes are not exercised on `main` until a rebuild runs. Use `force` to test one.

## Supersedes
None
