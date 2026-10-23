# Decision: Static Astro site fed by per-build records on a site-data branch

Status: accepted
Date: 2026-10-22

## Context
The images need a public site listing every image, a builder that resolves a selection to a tag, a feature matrix, per-image history and a changelog. History cannot come from GHCR alone: ADR 0007 deletes superseded digests after a day, and a rebuild in place (ADR 0009) moves a tag without leaving a tagged trace. ADR 0003 keeps rebuild decisions on image labels; this is display state only.

## Decision
- `site/` is an Astro project built to static HTML and deployed to GitHub Pages by `.github/workflows/site.yml`.
- The build workflow's merge job writes one JSON record per published manifest (time, run, commit, digest, per-arch digests, full PHP version, tags, `php -m` modules, amd64 labels) and uploads it as an artifact. The `site` job, called from `build.yml` after `merge`, copies the records into the orphan `site-data` branch as one file each under `records/`, pushes with a rebase retry, builds and deploys.
- When `site-data` does not exist, `scripts/backfill-records.sh` seeds it from every currently tagged GHCR image.
- Tags, versions and extensions are read from `versions.json`, record tags and `scripts/tags.sh`, and the Usage page reads the proxy table from `README.md`; nothing on the site duplicates them by hand.
- The records are the only stored state: every page, including one per image and one per build, is regenerated from them on each site build.
- Site-only changes run `site.yml` on their own; `build.yml` ignores `site/**` so they never rebuild images.

## Consequences
- History is complete from the first site run onwards; anything before that is limited to what was still tagged at backfill.
- One file per record means parallel runs never conflict on push. Deploys are not serialised by a concurrency group, which would drop a queued run and its records; instead a run skips its deploy when `site-data` has moved on since it built, leaving it to the newer run.
- A build recorded by both the backfill and its own run is shown once, from the run's record.
- Records are never pruned; at ~40 records per full build the branch grows by a few MB a year.
- The repository's Pages source must be set to GitHub Actions.

## Supersedes
None
