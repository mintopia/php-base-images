# Decision: Published image labels are the record of upstream inputs

Status: accepted
Date: 2026-10-24

## Context
The daily check must rebuild a Lane only when an input has changed upstream. It needs a record of what each published image was built from. Options were a state file committed to the repo, an external store, or the image itself.

## Decision
- Every published image carries OCI labels for its inputs: `org.opencontainers.image.base.digest` (the OS base image), `net.mintopia.php.source` and `net.mintopia.php.tag`, `net.mintopia.frankenphp.version`, `net.mintopia.ext.<name>.version` for each extension, `net.mintopia.nginx.version` and `net.mintopia.s6.version`.
- The daily check reads the labels of each published target with `docker buildx imagetools inspect`, for each architecture, and compares them to the current upstream values. A difference makes the target stale.
- `scripts/resolve-matrix.sh` looks up the current upstream values: Docker Hub digests, Alpine and nginx.org and Debian package indexes, Packagist, and GitHub releases.
- A failed upstream lookup fails the resolve job, so nothing is rebuilt that run.

## Consequences
- No state is kept outside GHCR. Deleting an image makes its target stale, so it is rebuilt.
- A new tracked input needs a new label and a new comparison in `scripts/resolve-matrix.sh`.
- The labels describe what the image was built from, not what it contains. Fixable OS CVEs are checked separately (ADR 0022).

## Supersedes
None
