# Decision: Build records on a site-data branch feed a static site

Status: accepted
Date: 2026-10-24

## Context
The site lists every image, every build and its history. GHCR alone cannot give that history: superseded tags move, and untagged builds are hard to identify. The records are display state only. Rebuild decisions come from image labels (ADR 0021).

## Decision
- The merge job writes one JSON record per published manifest. A record has the time, run, commit, image, version, OS, Variant, PHP version, stable flag, digest, package ID, per-arch platforms, tags, loaded modules, sizes and labels.
- The `site` job in `site.yml`, called by `build.yml` after every PHP version's call, appends the records as one file each under `records/` on the orphan `site-data` branch. A push that loses a race is retried after a rebase, up to 5 times.
- When `site-data` does not exist, `scripts/backfill-records.sh` seeds it from every published multi-arch index on GHCR, tagged or not. Single-platform lane pushes are skipped. A rerun skips digests already recorded.
- `site/` is an Astro project built to static HTML. Each build regenerates every page from the records. Versions, tags and extensions come from `versions.json`, `scripts/tags.sh` and the records. The Usage page reads the proxy table from `README.md`.
- The site deploys at the end of every non-PR build run. The deploy job is in the `pages` concurrency group, with `cancel-in-progress: false`. A run skips its deploy if `site-data` has moved on since it built, so an older build never overwrites a newer one.
- `site.yml` also runs on pull requests that touch `site/`, and on manual dispatch. Those runs build but do not deploy.

## Consequences
- Each record is a separate file, so parallel runs never conflict.
- Records are never pruned. The branch grows by a few MB a year.
- History starts with the first run or the backfill. The backfill includes superseded builds, so they appear on the site too.
- A push to `main` that changes only `site/` still runs `build.yml`, because its push trigger has no path filter. That run runs the upstream check, then deploys.
- The repository's Pages source must be set to GitHub Actions.

## Supersedes
None
