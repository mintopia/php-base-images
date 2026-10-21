# Decision: Rebuild Lanes with fixable OS-package CVEs

Status: accepted
Date: 2026-10-21

## Context
The Upstream check (ADR 0003) rebuilds only when a labelled input changes. Distros ship security fixes as package updates without re-tagging the base image, so a published image can carry a CVE whose fix is already in the Alpine/Debian repos while every label still matches. A rebuild alone would not help either: the registry cache (ADR 0002) reuses the old `apk add`/`apt-get install` layer.

## Decision
- The Upstream check scans each still-current published image's BuildKit SBOM (amd64) with a pinned Trivy, OS packages only, `--ignore-unfixed`. Any hit marks the Lane stale. Scan failures warn and never block other rebuilds.
- Final stages run `apk upgrade` / `apt-get upgrade` after an `ARG PKG_STAMP`; CI sets it to the UTC date, so that one layer re-runs on every CI day while everything else stays cached.

## Consequences
- Fixable OS CVEs are patched within a day; CVEs in PHP, extensions, FrankenPHP/Caddy or s6 still need a version bump, which the label check already covers.
- Packages inherited from upstream bases may be newer than the base itself; the upgrade layer duplicates the changed files (small).
- Image builds on different days differ even with identical inputs.
- Unfixed CVEs are ignored: a rebuild cannot fix them.

## Supersedes
None (extends 0003-image-labels-as-upstream-state.md)
