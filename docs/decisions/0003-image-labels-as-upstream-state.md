# Decision: Published image labels are the only record of upstream inputs

Status: accepted
Date: 2026-10-21

## Context
A daily job must rebuild a lane only when PHP, the OS base, nginx, FrankenPHP, s6-overlay or an extension changed upstream. That needs a record of what each published image was built from. Options: a state file committed back to the repo, an external store, or the image itself.

## Decision
Every image carries OCI labels recording its inputs (base image digest, nginx version, s6-overlay version, extension versions). The daily check reads them with `docker buildx imagetools inspect`, compares to current upstream, and dispatches builds only for lanes that differ. Monthly cron and manual dispatch pass `force=true` to bypass the comparison.

## Consequences
- No state outside GHCR; deleting an image simply makes its lane rebuild.
- Adding a new tracked input means adding a label and a comparison; both in one place.
- The check depends on upstream query APIs (Docker Hub, nginx.org index, Packagist); an API outage delays rebuilds, it never causes a wrong one.

## Supersedes
None
