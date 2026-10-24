# Decision: Final stages upgrade OS packages on each CI day

Status: accepted
Date: 2026-10-24

## Context
Distros ship security fixes as package updates without re-tagging their base images. A rebuild that reuses cached `apk add` or `apt-get install` layers would not pick up those fixes.

## Decision
- Every final stage runs `apk upgrade --no-cache` or `apt-get upgrade -y` after `ARG PKG_STAMP`.
- `scripts/resolve-matrix.sh` sets `PKG_STAMP` to the UTC date of the run, so that layer and the ones after it run again each CI day. Earlier layers stay cached.

## Consequences
- A rebuild ships the current distro fixes. Fixable CVEs trigger rebuilds (ADR 0022).
- Identical inputs built on different days produce different images.
- The upgrade layer repeats the changed package files, which adds a small amount of size.
- A rebuild cannot fix a CVE with no fixed package. The scan ignores those.

## Supersedes
None
